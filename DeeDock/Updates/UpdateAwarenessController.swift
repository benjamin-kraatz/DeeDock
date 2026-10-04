#if DIRECT_DISTRIBUTION
import AppKit
import SwiftUI

/// Owns one nonactivating callout, centred under the menu bar of the main display.
///
/// The user's own choices (open, dismiss) let the callout animate out; every other reason to
/// remove it closes the panel at once. Stop removes the panels, the timer, and pending closes.
@MainActor
final class UpdateAwarenessController {
    let awareness: UpdateAwarenessStore
    var isBlocked: () -> Bool = { false }
    var targetScreen: () -> NSScreen? = { NSScreen.main }
    var openUpdate: () -> Void = {}
    var openWhatsNew: () -> Void = {}
    private var timer: Timer?
    private var panel: UpdateAwarenessPanel?
    /// What the open panel announces. A different announcement replaces the panel.
    private var shown: Announcement?
    /// Drives the open panel's departure animation.
    private var presentation: UpdateCalloutPresentation?
    /// A panel that is animating out, and the task that closes it afterwards.
    private var departing: (panel: UpdateAwarenessPanel, close: Task<Void, Never>)?

    private struct Announcement: Equatable {
        let kind: UpdateAwarenessCalloutView.Kind
        let version: String
    }
    private var observers: [NSObjectProtocol] = []

    init(awareness: UpdateAwarenessStore) {
        self.awareness = awareness
    }

    func start() {
        guard timer == nil else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        })
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        closePanel()
        finishDeparture()
        isBlocked = { false }
        targetScreen = { NSScreen.main }
        openUpdate = {}
        openWhatsNew = {}
    }

    private func refresh() {
        guard let announcement, !isBlocked() else {
            closePanel()
            return
        }
        if shown != announcement { closePanel() }
        guard panel == nil, let screen = targetScreen() ?? NSScreen.main else { return }
        present(announcement, on: screen)
    }

    /// A waiting offer outranks the installed notice, which a newer offer clears anyway.
    private var announcement: Announcement? {
        if awareness.showsCallout(), let version = awareness.offerVersion {
            return Announcement(kind: awareness.stagedSince == nil ? .available : .ready, version: version)
        }
        if awareness.showsInstalledCallout, !awareness.windowIsOpen {
            return Announcement(kind: .installed, version: AppVersionInfo.current.version)
        }
        return nil
    }

    private func present(_ announcement: Announcement, on screen: NSScreen) {
        let installed = announcement.kind == .installed
        let panel = UpdateAwarenessPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The island animates inside a transparent canvas and brings its own shadow; a window
        // shadow would be cached for the first frame's outline.
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .fullScreenNone]
        panel.isExcludedFromWindowsMenu = true
        let presentation = UpdateCalloutPresentation()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let view = NSHostingView(rootView: UpdateAwarenessCalloutView(
            kind: announcement.kind,
            version: announcement.version,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            reduceMotion: reduceMotion,
            presentation: presentation,
            open: { [weak self] in
                guard let self else { return }
                dismissPanel(reduceMotion: reduceMotion)
                if installed {
                    awareness.noteInstalledCalloutSeen()
                    openWhatsNew()
                } else {
                    awareness.noteWindowOpened()
                    openUpdate()
                }
            },
            dismiss: { [weak self] in
                guard let self else { return }
                if installed { awareness.noteInstalledCalloutSeen() } else { awareness.dismiss() }
                dismissPanel(reduceMotion: reduceMotion)
            }
        ))
        // The canvas hangs from the top of the visible frame, so the island appears to drop
        // out from under the menu bar. Its transparent margins pass clicks through.
        let size = view.fittingSize
        let available = screen.visibleFrame
        panel.setFrame(CGRect(x: available.midX - size.width / 2, y: available.maxY - size.height,
                              width: size.width, height: size.height), display: false)
        panel.contentView = view
        self.panel = panel
        self.presentation = presentation
        shown = announcement
        panel.orderFrontRegardless()
    }

    private func closePanel() {
        panel?.close()
        panel = nil
        presentation = nil
        shown = nil
    }

    /// Lets the open panel animate out, then closes it. The panel stops counting as shown
    /// immediately, so `refresh` neither cuts the animation short nor waits for it.
    private func dismissPanel(reduceMotion: Bool) {
        guard let panel, let presentation else { return }
        finishDeparture()
        self.panel = nil
        self.presentation = nil
        shown = nil
        presentation.isLeaving = true
        let close = Task { [weak self] in
            try? await Task.sleep(for: UpdateAwarenessCalloutView.departureDuration(reduceMotion: reduceMotion))
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

/// Becomes key only through an explicit click, never on presentation or hover.
private final class UpdateAwarenessPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
#endif
