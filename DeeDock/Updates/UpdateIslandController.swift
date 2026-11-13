import AppKit
import Observation
import SwiftUI

/// Owns the update island: one nonactivating panel under the menu bar of the main display.
///
/// The island is either a compact callout, which this controller shows from awareness state,
/// or the full update panel, which the user driver presents and dismisses. Opening a callout
/// morphs the same island into the panel. The user's own choices let the island animate
/// out; every other reason to remove it closes the panel at once. `stop` removes the
/// panels, the timer, the observers, and pending closes.
@MainActor
final class UpdateIslandController {
    private let presentation: UpdatePresentation
    private let awareness: UpdateAwarenessStore
    private let analytics: UpdateAnalytics
    private let action: (UpdateAction, UUID) -> Void
    private let close: () -> Void
    /// Dock activity that should keep a callout away. The panel ignores it.
    var isBlocked: () -> Bool = { false }
    var targetScreen: () -> NSScreen? = { NSScreen.main }
    var openUpdate: () -> Void = {}
    var openWhatsNew: () -> Void = {}
    /// The 1 Hz callout check. Armed only while a callout is due or one is up, see `needsTicks`.
    private var timer: Timer?
    /// One-shot at the moment a staged offer's callout becomes due, which nothing else announces.
    private var deadlineTimer: Timer?
    private var deadlineTimerDate: Date?
    /// True between `start()` and `stop()`.
    private var started = false
    /// Bumped by `stop()`, so a registration left over from a previous start cannot fork a second chain.
    private var trackingGeneration = 0
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var panel: UpdateIslandPanel?
    /// State of the open island. Nil exactly when `panel` is nil.
    private var model: UpdateIslandModel?
    /// The callout last reported as shown. Re-presenting it after a display change or a busy
    /// dock is not reported again.
    private var reportedCallout: UpdateIslandAnnouncement?
    /// An island that is animating out, and the task that closes it afterwards.
    private var departing: (panel: UpdateIslandPanel, close: Task<Void, Never>)?

    /// Whether the island currently shows the update panel. A callout does not count.
    var isVisible: Bool { model?.content == .panel }

    /// - Parameters:
    ///   - action: A panel button, with the callback generation it was rendered for.
    ///   - close: The panel's close button or Escape. The driver applies its phase policy.
    init(presentation: UpdatePresentation, awareness: UpdateAwarenessStore, analytics: UpdateAnalytics,
         action: @escaping (UpdateAction, UUID) -> Void, close: @escaping () -> Void) {
        self.presentation = presentation
        self.awareness = awareness
        self.analytics = analytics
        self.action = action
        self.close = close
    }

    /// Starts watching awareness state for callouts. The panel works without it.
    func start() {
        guard !started else { return }
        started = true
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        // A run-loop timer's fire date does not count time asleep, and a clock change moves the
        // deadline relative to it, so both reschedule the patience deadline from scratch.
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescheduleDeadline() }
        })
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescheduleDeadline() }
        })
        trackAwareness()
        refresh()
    }

    /// Releases the hosting hierarchy without invoking a user response.
    func stop() {
        started = false
        trackingGeneration += 1
        timer?.invalidate()
        timer = nil
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        deadlineTimerDate = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        closePanel()
        finishDeparture()
        isBlocked = { false }
        targetScreen = { NSScreen.main }
        openUpdate = {}
        openWhatsNew = {}
    }

    /// Shows the update panel, morphing an open callout into it.
    /// - Parameter activate: Gives the panel keyboard focus. DOKK itself is never activated.
    func present(activate: Bool) {
        awareness.noteWindowOpened()
        if let panel, let model {
            if model.content != .panel, let screen = panel.screen ?? targetScreen() ?? NSScreen.main {
                // Grow the canvas first; the island is anchored top-centre and stays put.
                layoutForPanel(panel, on: screen)
                model.content = .panel
            }
        } else if let screen = targetScreen() ?? NSScreen.main {
            show(.panel, on: screen)
        }
        if activate { panel?.makeKeyAndOrderFront(nil) } else { panel?.orderFrontRegardless() }
    }

    /// Folds the update panel away. The session stays reachable from the menu, and
    /// dismissal never implies permission to install.
    func dismiss() {
        awareness.noteWindowClosed()
        guard model?.content == .panel else { return }
        dismissPanel()
    }

    /// Whether the 1 Hz check has work: a callout is due (it may be blocked by dock activity,
    /// which has no notification), or a callout is up and may need closing.
    private var needsTicks: Bool {
        guard started else { return false }
        if let model, model.content != .panel { return true }
        return announcement != nil
    }

    /// When a staged offer's callout becomes due by time alone, or nil when that is not pending.
    /// Every other input to `announcement` is observed.
    private var calloutDeadline: Date? {
        guard awareness.showsIndicators, awareness.offerVersion != nil, !awareness.windowIsOpen,
              awareness.installWhenIdle, let stagedSince = awareness.stagedSince else { return nil }
        let deadline = stagedSince.addingTimeInterval(UpdateAwarenessStore.calloutPatience)
        return deadline > .now ? deadline : nil
    }

    /// Re-arms the timers whenever awareness state behind `announcement` changes. Observation
    /// fires once, so each change registers the next one; the chain ends with `stop()`.
    private func trackAwareness() {
        guard started else { return }
        let generation = trackingGeneration
        withObservationTracking {
            _ = announcement
            _ = calloutDeadline
            // `announcement` can skip this read; a closing Update window must still re-check.
            _ = awareness.windowIsOpen
        } onChange: { [weak self] in
            guard let self else { return }
            // `onChange` runs before the new value is stored; read it on the next main-actor turn.
            // A new callout still waits for the next tick, as it did when the tick ran all the
            // time. A cleared announcement is applied now, because the timer may stop with it:
            // that pass forgets the reported callout and closes a callout still up. A departing
            // island is already detached, so its animation is not cut short.
            Task { @MainActor in
                guard self.started, self.trackingGeneration == generation else { return }
                if self.announcement == nil { self.refresh() } else { self.updateTimers() }
                self.trackAwareness()
            }
        }
        updateTimers()
    }

    /// Matches the 1 Hz timer to `needsTicks` and the one-shot to `calloutDeadline`.
    private func updateTimers() {
        if needsTicks {
            if timer == nil {
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
                timer.tolerance = 0.25
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
        let deadline = started && announcement == nil ? calloutDeadline : nil
        guard deadline != deadlineTimerDate else { return }
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        deadlineTimerDate = deadline
        guard let deadline else { return }
        // The patience check is `>=`, and a timer never fires early, so the tick at the deadline
        // finds the callout due and arms the 1 Hz check from there.
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.deadlineTimer = nil
                self.deadlineTimerDate = nil
                self.refresh()
            }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        deadlineTimer = timer
    }

    /// Drops the pending one-shot and checks again, which reschedules it against the current clock.
    private func rescheduleDeadline() {
        guard started else { return }
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        deadlineTimerDate = nil
        refresh()
    }

    private func refresh() {
        refreshCallout()
        // Showing or closing a callout changes `needsTicks` without an awareness change.
        updateTimers()
    }

    private func refreshCallout() {
        if model?.content == .panel { return }
        guard let announcement else {
            reportedCallout = nil
            closePanel()
            return
        }
        guard !isBlocked() else {
            closePanel()
            return
        }
        if let model, model.content != .callout(announcement) { closePanel() }
        guard panel == nil, let screen = targetScreen() ?? NSScreen.main else { return }
        show(.callout(announcement), on: screen)
        panel?.orderFrontRegardless()
        if reportedCallout != announcement {
            reportedCallout = announcement
            analytics.callout(.shown, kind: announcement.kind)
        }
    }

    /// A waiting offer outranks the installed notice, which a newer offer clears anyway.
    private var announcement: UpdateIslandAnnouncement? {
        if awareness.showsCallout(), let version = awareness.offerVersion {
            return UpdateIslandAnnouncement(kind: awareness.stagedSince == nil ? .available : .ready, version: version)
        }
        if awareness.showsInstalledCallout, !awareness.windowIsOpen {
            return UpdateIslandAnnouncement(kind: .installed, version: AppVersionInfo.current.version)
        }
        return nil
    }

    private func show(_ content: UpdateIslandModel.Content, on screen: NSScreen) {
        // An island still folding away would overlap the new one.
        finishDeparture()
        let panel = UpdateIslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The island animates inside a transparent canvas and brings its own shadow; a window
        // shadow would be cached for the first frame's outline. The canvas's transparent
        // parts pass clicks through, which `ignoresMouseEvents = false` would switch off.
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        let model = UpdateIslandModel(content: content)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let view = NSHostingView(rootView: UpdateIslandView(
            model: model,
            presentation: presentation,
            awareness: awareness,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            reduceMotion: reduceMotion,
            openCallout: { [weak self] in self?.openCallout() },
            dismissCallout: { [weak self] in self?.dismissCallout() },
            action: action,
            close: close
        ))
        if content == .panel {
            layoutForPanel(panel, on: screen)
        } else {
            // A callout stays out of full-screen Spaces. Its canvas is sized for the tallest
            // callout, because the island starts as a bead and cannot be measured yet. It
            // hangs from the top of the visible frame, so the island appears to drop out
            // from under the menu bar.
            panel.collectionBehavior = [.transient, .fullScreenNone]
            let insets = UpdateIslandView.canvasInsets
            let size = CGSize(width: UpdateIslandView.calloutWidth + insets.leading + insets.trailing,
                              height: UpdateIslandView.calloutMaxHeight + insets.top + insets.bottom)
            let visible = screen.visibleFrame
            panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height,
                                  width: size.width, height: size.height), display: false)
        }
        // This controller owns the frame; the island's changing size must not resize the window.
        view.sizingOptions = []
        panel.contentView = view
        self.panel = panel
        self.model = model
    }

    /// Sizes the canvas for the tallest panel the screen allows. A requested panel also
    /// shows over full-screen apps.
    private func layoutForPanel(_ panel: UpdateIslandPanel, on screen: NSScreen) {
        let insets = UpdateIslandView.canvasInsets
        let visible = screen.visibleFrame
        let width = UpdateIslandView.panelWidth + insets.leading + insets.trailing
        let height = min(visible.height - 16, 760)
        panel.collectionBehavior = [.transient, .canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setFrame(CGRect(x: visible.midX - width / 2, y: visible.maxY - height, width: width, height: height),
                       display: true)
    }

    private func screensChanged() {
        guard let panel, let model else { return }
        if model.content == .panel, let screen = targetScreen() ?? NSScreen.main {
            layoutForPanel(panel, on: screen)
        } else {
            // The next refresh presents the callout again in the new arrangement.
            closePanel()
        }
    }

    private func openCallout() {
        guard case .callout(let announcement) = model?.content else { return }
        analytics.callout(.opened, kind: announcement.kind)
        if announcement.kind == .installed {
            awareness.noteInstalledCalloutSeen()
            openWhatsNew()
        } else {
            openUpdate()
        }
        // Opening normally turns this island into the panel through `present`. When nothing
        // took it over, such as a check Sparkle starts later, it leaves like a dismissal.
        guard model?.content != .panel else { return }
        if announcement.kind != .installed { awareness.dismiss() }
        dismissPanel()
    }

    private func dismissCallout() {
        guard case .callout(let announcement) = model?.content else { return }
        analytics.callout(.dismissed, kind: announcement.kind)
        if announcement.kind == .installed { awareness.noteInstalledCalloutSeen() } else { awareness.dismiss() }
        dismissPanel()
    }

    private func closePanel() {
        panel?.close()
        panel = nil
        model = nil
    }

    /// Lets the open island animate out, then closes it. It stops counting as open
    /// immediately, so `refresh` neither cuts the animation short nor waits for it.
    private func dismissPanel() {
        guard let panel, let model else { return }
        finishDeparture()
        self.panel = nil
        self.model = nil
        model.isLeaving = true
        let duration = UpdateIslandView.departureDuration(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let close = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.finishDeparture()
        }
        departing = (panel, close)
    }

    private func finishDeparture() {
        departing?.close.cancel()
        departing?.panel.close()
        departing = nil
    }
}

/// Becomes key only through an explicit click or a requested panel, never on hover.
private final class UpdateIslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
