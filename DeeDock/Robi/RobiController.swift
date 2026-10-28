import AppKit
import ApplicationServices
import ClaudeForFoundationModels
import Observation
import SwiftUI

/// Robi on the focused window.
///
/// Owns the window tracker, the companion panel, the selection sheet and the agent, and moves Robi
/// through its phases: asleep, awake on hover, selecting, prompting, thinking, answered. Everything
/// it starts (observers, monitors, timers, tasks, panels) ends in `halt()`, which runs when Robi is
/// turned off, loses Accessibility, or DOKK stops.
///
/// Robi never activates DOKK. Its panels are non-activating, so the app underneath stays
/// frontmost and keeps its selection; the panel takes the keyboard only while a question is typed.
@MainActor @Observable
final class RobiController {
    let store: RobiStore
    /// False when another app owns Option-Shift-Command-R; Settings says so.
    private(set) var shortcutAvailable = true
    /// Robi is on but cannot show itself until Accessibility is granted.
    private(set) var needsAccessibility = false

    /// Sets the Settings route to Robi's page before the Settings window opens.
    @ObservationIgnored var prepareSettingsRoute: () -> Void = {}
    /// Tells Discovery that Robi has been used.
    @ObservationIgnored var didUse: () -> Void = {}

    @ObservationIgnored private let model = RobiModel()
    @ObservationIgnored private let eyes = RobiEyes()
    @ObservationIgnored private let tracker = RobiWindowTracker()
    @ObservationIgnored private let capture = RobiCapture()
    @ObservationIgnored private let agent = RobiAgent()
    @ObservationIgnored private let shortcut = RobiShortcut()
    @ObservationIgnored private var panel: RobiPanel?
    @ObservationIgnored private var sheet: RobiSelectionSheet?
    /// Rings a landmark the answer referred to; made the first time a reference is clicked.
    @ObservationIgnored private var spotlight: RobiSpotlight?
    /// Flies a picked region into the face; made the first time a region is picked.
    @ObservationIgnored private var flight: RobiFlight?
    /// Startles the face when the flight lands and calms it again. Cancelled with the flight.
    @ObservationIgnored private var surpriseTask: Task<Void, Never>?
    /// Groups one interaction's model calls in LLM analytics: its suggested questions and answers.
    @ObservationIgnored private var trace = AIObservability.makeTrace()
    @ObservationIgnored private var panelSize = CGSize.zero
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var pointerMonitors: [Any] = []
    @ObservationIgnored private var blinkTimer: Timer?
    @ObservationIgnored private var circles = RobiCircleDetector()
    /// Ends the dizzy spin, and keeps the next one from starting straight away.
    @ObservationIgnored private var dizzyTask: Task<Void, Never>?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var shrinkTask: Task<Void, Never>?
    @ObservationIgnored private var presenceTask: Task<Void, Never>?
    @ObservationIgnored private var tintTask: Task<Void, Never>?
    @ObservationIgnored private var contextTask: Task<Void, Never>?
    /// Reads the app's menu bar once per interaction, as soon as Robi is summoned.
    @ObservationIgnored private var menuTask: Task<RobiMenuCatalog, Never>?
    /// Runs the proposed steps after the person clicked Run.
    @ObservationIgnored private var runTask: Task<Void, Never>?
    /// The pinned window lost focus while steps ran; Robi closes when the run ends.
    @ObservationIgnored private var leftDuringRun = false
    @ObservationIgnored private var answerTask: Task<Void, Never>?
    /// Asks the on-device model for suggested questions while the prompt bar is open. Cancelled
    /// as soon as the prompt closes: a question is asked, Robi is dismissed, or the interaction ends.
    @ObservationIgnored private var suggestTask: Task<Void, Never>?
    /// The question `answerTask` is answering, for reporting a stop.
    @ObservationIgnored private var answering: (intent: RobiIntent, started: Date)?
    /// The generation of the answer on screen. Every question gets a new one, and a stop or an
    /// ending moves on to a fresh one, so updates from an answer that is gone are dropped. The
    /// menu tool reports outside the answer's task, so cancellation alone cannot stop it.
    @ObservationIgnored private var answerGeneration = 0
    /// Hands out generations. Never reused, so a restored answer's generation stays unique.
    @ObservationIgnored private var generations = 0
    /// The answer set aside on another window, if any.
    @ObservationIgnored private var parked: RobiParked?
    @ObservationIgnored private var parkedExpiry: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var selection: RobiSelection?
    @ObservationIgnored private var webChange: RobiWebAccessibility.Change = .none
    /// A question waiting for an API key to be entered in the card.
    @ObservationIgnored private var pending: (intent: RobiIntent, text: String)?
    @ObservationIgnored private var hovering = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var running = false
    @ObservationIgnored private var trigger: AnalyticsTrigger = .click
    /// Picking again after stepping back from the question field, where a click collapses Robi
    /// instead of taking the whole window.
    @ObservationIgnored private var isPickingAgain = false
    /// Springs a released goo pull back to the edge.
    @ObservationIgnored private var gooTask: Task<Void, Never>?
    /// The press on the face being followed, from mouse-down to release.
    @ObservationIgnored private var facePress: RobiFacePress?
    /// Where the tab was dragged on each window this session, as in `RobiLayout.tabX`. Wins over
    /// the app's saved position, so two windows of one app can differ. Entries for closed windows
    /// stay until DOKK quits or positions are reset; there is one small number per dragged window.
    @ObservationIgnored private var windowPositions: [CGWindowID: Double] = [:]
    /// What is left of a released drag's rubber band while it springs back.
    @ObservationIgnored private var settleStretch: CGFloat = 0
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    /// Nil creates the store that reads and writes Robi's real preferences.
    init(store: RobiStore? = nil) {
        self.store = store ?? RobiStore()
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        store.changed = { [weak self] in self?.configure() }
        let workspace = NSWorkspace.shared.notificationCenter
        // Accessibility is usually granted in System Settings and noticed when the person comes back.
        tokens.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configureIfTrustChanged() }
        })
        tokens.append(workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.accessibilityOptionsChanged() }
        })
        configure()
    }

    func stop() {
        guard started else { return }
        started = false
        store.changed = nil
        tokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        tokens = []
        shortcut.stop()
        halt()
    }

    private func configure() {
        let settings = store.settings
        model.answerModel = settings.answerModel
        model.claudeModel = settings.claudeModel
        model.claudeEffort = settings.claudeEffort
        model.attachesWindowPicture = settings.attachWindowPicture
        tracker.excludedBundleIdentifiers = Set(settings.excludedBundleIdentifiers)
        // Reset Tab Positions empties the saved ones; this session's per-window ones go with them.
        if settings.tabPositions.isEmpty, !windowPositions.isEmpty {
            windowPositions = [:]
            layout()
        }
        let trusted = AXIsProcessTrusted()
        needsAccessibility = settings.isEnabled && !trusted
        if settings.isEnabled && trusted { run() } else { halt() }
        if running && settings.shortcutEnabled {
            if !shortcut.isRegistered { shortcutAvailable = shortcut.start { [weak self] in self?.summon(.hotkey) } }
        } else {
            shortcut.stop()
            shortcutAvailable = true
        }
    }

    private func configureIfTrustChanged() {
        guard store.settings.isEnabled, AXIsProcessTrusted() != running else { return }
        configure()
    }

    private func run() {
        guard !running else { return }
        running = true
        let panel = panel ?? makePanel()
        self.panel = panel
        tracker.targetChanged = { [weak self] target in self?.targetChanged(target) }
        tracker.frameChanged = { [weak self] frame in self?.layout(frame: frame) }
        tracker.leftWhilePinned = { [weak self] departure in self?.leftWindow(departure) }
        tracker.start()
        Task { [capture] in await capture.prewarm() }
    }

    private func halt() {
        guard running else { return }
        running = false
        endInteraction()
        dropParked()
        tracker.stop()
        tracker.targetChanged = nil
        tracker.frameChanged = nil
        tracker.leftWhilePinned = nil
        stopPointerTracking()
        [sleepTask, shrinkTask, presenceTask, tintTask, settleTask].forEach { $0?.cancel() }
        facePress = nil
        settleStretch = 0
        resetGoo()
        model.isPresent = false
        model.phase = .idle
        panel?.orderOut(nil)
    }

    private func makePanel() -> RobiPanel {
        var actions = RobiActions()
        actions.tapFace = { [weak self] in self?.summon(.click) }
        actions.faceGesture = { [weak self] gesture in self?.faceGesture(gesture) }
        actions.submit = { [weak self] text in self?.ask(.custom, text: text) }
        actions.suggest = { [weak self] intent in self?.ask(intent, text: String(localized: intent.title)) }
        actions.askSuggested = { [weak self] question in self?.ask(.suggested, text: question) }
        actions.copy = { [weak self] in self?.copyAnswer() }
        actions.replace = { [weak self] in self?.replaceSelection() }
        actions.paste = { [weak self] in self?.pasteAnswer() }
        actions.runProposal = { [weak self] in self?.runProposal() }
        actions.point = { [weak self] landmark in self?.point(at: landmark) }
        actions.toggleWindowPicture = { [weak self] in self?.toggleWindowPicture() }
        actions.saveClaudeKey = { [weak self] key in self?.saveClaudeKey(key) }
        actions.answerOnDevice = { [weak self] in self?.answerPendingOnDevice() }
        actions.openSettings = { [weak self] in self?.openSettings() }
        actions.stop = { [weak self] in self?.stopAnswer() }
        actions.dismiss = { [weak self] in self?.dismiss() }
        let panel = RobiPanel()
        let host = RobiHostingView(rootView: RobiRootView(model: model, eyes: eyes, actions: actions))
        host.sizingOptions = []
        host.hoverChanged = { [weak self] inside in self?.hover(inside) }
        panel.contentView = host
        return panel
    }

    // MARK: Following the window

    private func targetChanged(_ target: RobiWindowTarget?) {
        if model.phase.isEngaged { endInteraction() }
        // A drag belongs to the window it started on; its release must not move another's tab.
        facePress = nil
        settleTask?.cancel()
        settleStretch = 0
        resetGoo()
        // The tracker watches only the focused window, so a set-aside answer's window closing
        // is noticed here, on the next focus change.
        if let parked, !RobiWindowServer.exists(parked.windowID) { dropParked() }
        presenceTask?.cancel()
        guard model.isPresent else { return show(target) }
        // Retract into the old window, then emerge from the new one.
        model.isPresent = false
        let delay = model.reduceMotion ? 120 : 200
        presenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            self?.show(self?.tracker.target)
        }
    }

    private func show(_ target: RobiWindowTarget?) {
        guard let target, let panel else {
            panel?.orderOut(nil)
            model.isPresent = false
            if model.phase != .idle { setPhase(.idle) }
            return
        }
        model.applicationName = target.applicationName
        if model.phase != .idle && !hovering { setPhase(.idle) }
        layout()
        panel.orderFrontRegardless()
        model.isPresent = true
        sampleTint()
        if parked?.windowID == target.windowID { restoreParked() }
    }

    /// Places the panel on the window. `frame` overrides the tracker's frame during a predicted drag.
    private func layout(frame override: CGRect? = nil) {
        guard let target = tracker.target, let panel else { return }
        let space = RobiScreenSpace.current
        let window = space.appKitRect(fromTopLeft: override ?? target.frame)
        let display = space.display(for: window)
        let placement = RobiLayout.placement(window: window, isFullScreen: target.isFullScreen, display: display)
        if model.placement != placement { model.placement = placement }
        if panelSize == .zero { panelSize = model.panelSize(for: model.phase) }
        // While the tab is dragged its position comes from the pointer, so tracker updates that
        // arrive meanwhile place it where the drag has it instead of fighting it.
        let drag = facePress?.isDragging == true ? facePress : nil
        let frame = RobiLayout.panelFrame(window: window, placement: placement, size: panelSize, display: display,
                                          position: drag?.position ?? tabPosition(for: target),
                                          stretch: drag?.stretch ?? settleStretch)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        sheet?.move(over: window)
        spotlight?.move(over: window)
    }

    private func setPhase(_ phase: RobiPhase) {
        let next = model.panelSize(for: phase)
        // Grow first so nothing clips while the morph runs; shrink once it has finished.
        panelSize = CGSize(width: max(panelSize.width, next.width), height: max(panelSize.height, next.height))
        model.phase = phase
        layout()
        shrinkTask?.cancel()
        if panelSize != next {
            shrinkTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, let self, self.model.phase == phase else { return }
                self.panelSize = next
                self.layout()
            }
        }
        if phase == .idle { stopPointerTracking() } else { startPointerTracking() }
    }

    private func sampleTint() {
        guard let target = tracker.target else { return }
        tintTask?.cancel()
        let half = RobiMetrics.tabWidth / 2
        let space = RobiScreenSpace.current
        let window = space.appKitRect(fromTopLeft: target.frame)
        let centre = RobiLayout.tabX(window: window, position: tabPosition(for: target), display: space.display(for: window)) - window.minX
        tintTask = Task { [weak self, capture] in
            guard let color = await capture.tint(windowID: target.windowID, footprint: (centre - half)...(centre + half)),
                  !Task.isCancelled, let self, self.tracker.target?.windowID == target.windowID else { return }
            let rgb = color.usingColorSpace(.sRGB) ?? color
            let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
            self.model.tint = Color(nsColor: rgb)
            self.model.tintIsDark = luminance < 0.5
        }
    }

    // MARK: Moving the tab

    /// Where the tab goes on a window: where it was dragged on that window this session, else
    /// where it was last dragged on any of the app's windows, else nil, which centres it.
    private func tabPosition(for target: RobiWindowTarget) -> Double? {
        windowPositions[target.windowID] ?? target.bundleIdentifier.flatMap { store.settings.tabPositions[$0] }
    }

    /// The tracker's window in AppKit points, and the display holding it.
    private func targetGeometry() -> (window: CGRect, display: RobiScreenSpace.Display?)? {
        guard let target = tracker.target else { return nil }
        let space = RobiScreenSpace.current
        let window = space.appKitRect(fromTopLeft: target.frame)
        return (window, space.display(for: window))
    }

    private func faceGesture(_ gesture: RobiFaceGesture) {
        switch gesture {
        case .changed: facePointerMoved()
        case .ended: faceReleased(clicked: true)
        case .cancelled: faceReleased(clicked: false)
        }
    }

    /// The first report of a press is its mouse-down. Later ones turn it into a drag once the
    /// pointer is past the threshold, in every phase but selecting, where the tab stays put.
    ///
    /// Positions come from `NSEvent.mouseLocation` (AppKit screen points), the same space as the
    /// window rect, so the tab moves exactly as far as the pointer while the panel moves under it.
    private func facePointerMoved() {
        let pointer = NSEvent.mouseLocation
        guard var press = facePress else {
            var tabX: CGFloat?
            if let target = tracker.target, let geometry = targetGeometry() {
                tabX = RobiLayout.tabX(window: geometry.window, position: tabPosition(for: target), display: geometry.display)
                    + settleStretch
            }
            facePress = RobiFacePress(start: pointer, canDrag: model.phase != .selecting && tabX != nil,
                                      grip: pointer.x - (tabX ?? pointer.x))
            return
        }
        if press.isStretching { return stretchGoo(press, pointer: pointer) }
        guard press.canDrag, let geometry = targetGeometry() else { return }
        if !press.isDragging {
            guard press.hasLeftClickDistance(pointer) else { return }
            if canStretchGoo {
                press.isStretching = true
                facePress = press
                return startGoo(press, pointer: pointer)
            }
            press.isDragging = true
            settleTask?.cancel()
            settleStretch = 0
        }
        let wanted = pointer.x - press.grip
        let position = RobiLayout.position(forTabX: wanted, window: geometry.window, display: geometry.display)
        let overshoot = wanted - RobiLayout.tabX(window: geometry.window, position: position, display: geometry.display)
        press.position = position
        press.stretch = model.reduceMotion ? 0 : RobiLayout.rubberBand(overshoot)
        facePress = press
        // Placed directly, without animation, so the tab never lags the pointer.
        layout()
    }

    /// A press that never became a drag is a click. While selecting, when the press cannot drag,
    /// it counts only if released over Robi's panel, like a button. A drag drops the tab and
    /// remembers the spot. A cancelled press does neither.
    private func faceReleased(clicked: Bool) {
        guard let press = facePress else { return }
        facePress = nil
        if press.isStretching {
            snapGoo()
        } else if press.isDragging {
            dropTab(press)
        } else if clicked, press.canDrag || panel?.frame.contains(NSEvent.mouseLocation) == true {
            summon(.click, shift: NSEvent.modifierFlags.contains(.shift))
        }
        // A drag can carry the pointer off the tab; an awake Robi then falls asleep as usual.
        if !hovering { hover(false) }
    }

    // MARK: Goo

    /// A Shift-drag on a collapsed tab hanging inside the window pulls it away from the edge like
    /// goo instead of moving it. Above the window there is nowhere to pull it, and Reduce Motion
    /// keeps the plain drag.
    private var canStretchGoo: Bool {
        NSEvent.modifierFlags.contains(.shift) && model.placement == .inside && !model.reduceMotion
            && (model.phase == .idle || model.phase == .awake)
    }

    /// Grows the panel to hold the furthest pull and lean, so the goo never clips; the extra
    /// room is transparent and lets clicks through. The tab keeps its place: the panel's top
    /// edge stays on the window's edge and it grows evenly to both sides.
    private func startGoo(_ press: RobiFacePress, pointer: CGPoint) {
        gooTask?.cancel()
        let base = model.panelSize(for: model.phase)
        panelSize = CGSize(width: base.width + 2 * RobiGoo.leanLimit, height: base.height + RobiGoo.pullLimit + 10)
        layout()
        stretchGoo(press, pointer: pointer)
    }

    /// Follows the pointer with resistance. AppKit's y axis points up, so pulling down is a
    /// negative y offset from where the press began.
    private func stretchGoo(_ press: RobiFacePress, pointer: CGPoint) {
        let offset = CGSize(width: pointer.x - press.start.x, height: press.start.y - pointer.y)
        model.goo = RobiGoo.stretch(for: offset)
    }

    /// Lets go: the goo snaps back to the edge, overshoots into a little squash and settles. The
    /// panel shrinks back once it is still.
    private func snapGoo() {
        gooTask?.cancel()
        let from = model.goo
        let start = Date()
        gooTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                let remaining = RobiGoo.remaining(after: Date().timeIntervalSince(start))
                self.model.goo = CGSize(width: from.width * remaining,
                                        height: max(-RobiGoo.squashLimit, from.height * remaining))
                if remaining == 0 {
                    self.panelSize = self.model.panelSize(for: self.model.phase)
                    self.layout()
                    self.gooTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    /// Ends any goo at once, for when the tab leaves its window or Robi stops.
    private func resetGoo() {
        gooTask?.cancel()
        gooTask = nil
        guard model.goo != .zero else { return }
        model.goo = .zero
        panelSize = model.panelSize(for: model.phase)
    }

    /// Remembers the drop for this window and for its app, then springs back from any rubber band.
    private func dropTab(_ press: RobiFacePress) {
        guard let position = press.position, let target = tracker.target else { return layout() }
        windowPositions[target.windowID] = position
        if let bundle = target.bundleIdentifier { store.setTabPosition(position, for: bundle) }
        settle(from: press.stretch)
        // The title bar can have another colour here, like a browser's tab strip.
        sampleTint()
    }

    /// Springs a rubber-banded tab back onto its track. Every step lays the panel out again, so a
    /// window update meanwhile uses the spring's current offset instead of fighting it. Reduce
    /// Motion has no rubber band, so there is nothing to spring back from.
    private func settle(from stretch: CGFloat) {
        settleTask?.cancel()
        guard stretch != 0, !model.reduceMotion else {
            settleStretch = 0
            return layout()
        }
        let start = Date()
        settleTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                let remaining = RobiTabSpring.remaining(after: Date().timeIntervalSince(start))
                self.settleStretch = stretch * remaining
                self.layout()
                if remaining == 0 { return }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    // MARK: Hover, eyes, blink

    private func hover(_ inside: Bool) {
        hovering = inside
        sleepTask?.cancel()
        if inside {
            if model.phase == .idle {
                setPhase(.awake)
                sampleTint()
            }
        } else if model.phase == .awake {
            sleepTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1_600))
                // A held press keeps Robi awake even when a drag carries the pointer off the tab;
                // the release asks again.
                guard !Task.isCancelled, let self, self.model.phase == .awake, !self.hovering, self.facePress == nil else { return }
                self.setPhase(.idle)
            }
        }
    }

    /// Pointer monitors and the blink timer run only while Robi is awake or busy. Asleep, Robi
    /// costs nothing beyond window tracking.
    private func startPointerTracking() {
        if pointerMonitors.isEmpty {
            let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.updatePupils() }
            }) { pointerMonitors.append(global) }
            if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
                self?.updatePupils()
                return event
            }) { pointerMonitors.append(local) }
            updatePupils()
        }
        if blinkTimer == nil, !model.reduceMotion {
            let timer = Timer(timeInterval: 3.4, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.blink() }
            }
            RunLoop.main.add(timer, forMode: .common)
            blinkTimer = timer
        }
    }

    private func stopPointerTracking() {
        pointerMonitors.forEach(NSEvent.removeMonitor)
        pointerMonitors = []
        blinkTimer?.invalidate()
        blinkTimer = nil
        dizzyTask?.cancel()
        dizzyTask = nil
        circles.reset()
        eyes.dizzy = nil
        calm()
        eyes.isBlinking = false
        eyes.pupil = CGSize(width: 0, height: 2)
    }

    private func blink() {
        eyes.isBlinking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.eyes.isBlinking = false }
    }

    /// The face's centre in AppKit screen points, read off the panel's frame: at the bar's
    /// leading end while the bar is open (side margin, flare, the row's padding, half the compact
    /// face), in the middle of the tab otherwise; vertically the middle of the tab, which sits
    /// under the shadow margin when the tab is above the window. The pupils and the flight of a
    /// picked region both aim here.
    private func faceCentre() -> CGPoint? {
        guard let panel else { return nil }
        let frame = panel.frame
        let x = model.phase.isBar ? frame.minX + RobiMetrics.sideMargin + RobiMetrics.flare + 7 + 20 : frame.midX
        let tabTop = model.placement == .above ? frame.maxY - RobiMetrics.shadowMargin : frame.maxY
        return CGPoint(x: x, y: tabTop - RobiMetrics.tabHeight / 2)
    }

    /// Points the pupils at the pointer, reaching full deflection 140 pt away.
    private func updatePupils() {
        guard !model.reduceMotion, let face = faceCentre() else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - face.x, dy = mouse.y - face.y
        let distance = max(1, hypot(dx, dy))
        let reach = min(1, distance / 140)
        let next = CGSize(width: dx / distance * 2.6 * reach, height: -dy / distance * 2.2 * reach)
        if abs(next.width - eyes.pupil.width) > 0.05 || abs(next.height - eyes.pupil.height) > 0.05 { eyes.pupil = next }
        noticeCircling(dx: dx, dy: dy)
    }

    /// The easter egg: a full circle of the pointer around the face, while its eyes are wide open,
    /// makes Robi dizzy. Not while asleep, picking, or waiting for an answer, when the eyes are
    /// busy with something else; not again until the spin is over.
    private func noticeCircling(dx: CGFloat, dy: CGFloat) {
        guard dizzyTask == nil, model.phase != .idle, model.phase != .selecting, model.phase != .thinking,
              let clockwise = circles.add(dx: Double(dx), dy: Double(dy), at: .now) else { return }
        eyes.dizzy = RobiDizzy(start: .now, clockwise: clockwise)
        dizzyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(RobiDizzy.duration))
            guard !Task.isCancelled, let self else { return }
            self.eyes.dizzy = nil
            // A short rest so a pointer still circling doesn't set it off again at once.
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            self.circles.reset()
            self.dizzyTask = nil
        }
    }

    // MARK: Surprise

    /// Sends the picked region flying from where it was drawn into the face, and startles the
    /// face as it lands. Runs beside the capture and the morph into the prompt bar: nothing waits
    /// for it, and a pick made while one is still in the air starts both over. Call after
    /// `enterPrompt()`, so the face is where the bar puts it.
    private func fly(_ region: CGRect, from target: RobiWindowTarget) {
        guard let face = faceCentre() else { return }
        let window = RobiScreenSpace.current.appKitRect(fromTopLeft: target.frame)
        let path = RobiFlightPath(region: region, window: window, face: face, reduceMotion: model.reduceMotion)
        let flight = flight ?? RobiFlight()
        self.flight = flight
        flight.show(path, above: panel)
        surpriseTask?.cancel()
        surpriseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(path.landing))
            guard !Task.isCancelled, let self else { return }
            self.startle()
            try? await Task.sleep(for: .seconds(RobiSurprise.duration))
            guard !Task.isCancelled else { return }
            self.eyes.surprised = nil
            self.surpriseTask = nil
        }
    }

    /// The piece hit the face. A spin still going ends here: both want the pupils and the mouth,
    /// and being hit is the better reason to stop seeing stars.
    private func startle() {
        if dizzyTask != nil {
            dizzyTask?.cancel()
            dizzyTask = nil
            circles.reset()
            eyes.dizzy = nil
        }
        eyes.surprised = RobiSurprise(start: .now)
    }

    /// Ends the surprise, landed or still on its way.
    private func calm() {
        surpriseTask?.cancel()
        surpriseTask = nil
        eyes.surprised = nil
    }

    private func accessibilityOptionsChanged() {
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        if model.phase != .idle {
            stopPointerTracking()
            startPointerTracking()
        }
    }

    // MARK: Selection

    /// The face was clicked or the shortcut pressed.
    ///
    /// Plain clicks walk forward to the question field and then back the same way: collapsed,
    /// picking, field, picking again, collapsed. While picking the first time, a click takes the
    /// whole window; picking after stepping back, it collapses. A Shift-click jumps between
    /// collapsed and the field, taking the whole window on the way in, and collapses from picking.
    /// The shortcut never counts as Shift, although it contains it. An answer card always closes.
    private func summon(_ trigger: AnalyticsTrigger, shift: Bool = false) {
        guard running else { return }
        switch model.phase {
        case .idle, .awake:
            guard tracker.target != nil else { return NSSound.beep() }
            begin(trigger, wholeWindow: shift)
        case .selecting:
            if shift || isPickingAgain { dismiss() } else { takeWindow() }
        case .prompting:
            if shift { dismiss() } else { pickAgain() }
        case .thinking, .answered:
            dismiss()
        }
    }

    /// Steps back from the question field to picking, dropping the context that was picked.
    private func pickAgain() {
        contextTask?.cancel()
        contextTask = nil
        cancelSuggestions()
        selection = nil
        model.context = nil
        model.isReadingContext = false
        model.canReplace = false
        model.prompt = ""
        model.generatedSuggestions = []
        // The sheet takes the keyboard for Escape and Return, so the field gives it up first.
        panel?.allowsKey = false
        if panel?.isKeyWindow == true { panel?.resignKey() }
        isPickingAgain = true
        showSheet()
    }

    /// Text selected in the app becomes the context straight away. Without a selection, Robi
    /// enters selection mode, or with `wholeWindow` takes the whole window at once. Electron and
    /// Chromium apps get their web tree switched on first and are read once more a moment later,
    /// since their selection is invisible to AX until then.
    private func begin(_ trigger: AnalyticsTrigger, wholeWindow: Bool = false) {
        guard let target = tracker.target else { return }
        self.trigger = trigger
        trace = AIObservability.makeTrace()
        isPickingAgain = false
        tracker.isPinned = true
        didUse()
        let pid = target.processIdentifier
        menuTask = Task { await RobiMenuCommands.read(processIdentifier: pid) }
        if let found = RobiSelectionReader.selection(processIdentifier: pid) { return useSelection(found) }
        if let application = NSRunningApplication(processIdentifier: pid) { webChange = RobiWebAccessibility.enable(for: application) }
        if wholeWindow { return takeWindow() }
        showSheet()
        contextTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, self.model.phase == .selecting,
                  let found = RobiSelectionReader.selection(processIdentifier: pid) else { return }
            self.sheet?.close()
            self.useSelection(found)
        }
    }

    private func useSelection(_ found: RobiSelection) {
        selection = found
        model.context = RobiContext(kind: .selection, text: found.text)
        model.canReplace = found.isReplaceable
        enterPrompt()
        suggestQuestions()
    }

    private func showSheet() {
        guard let target = tracker.target else { return }
        let sheet = sheet ?? RobiSelectionSheet()
        self.sheet = sheet
        sheet.regionPicked = { [weak self] region in self?.takeRegion(region) }
        sheet.windowPicked = { [weak self] in self?.takeWindow() }
        sheet.cancelled = { [weak self] in self?.dismiss() }
        setPhase(.selecting)
        sheet.show(over: RobiScreenSpace.current.appKitRect(fromTopLeft: target.frame), below: panel)
    }

    /// A region was dragged on the sheet. The prompt bar opens at once; the region flies into the
    /// face meanwhile and is captured and read in the background.
    private func takeRegion(_ region: CGRect) {
        guard let target = tracker.target else { return }
        contextTask?.cancel()
        guard CGPreflightScreenCaptureAccess() else {
            sheet?.close()
            return showNotice(.screenRecordingNeeded)
        }
        model.context = RobiContext(kind: .region, text: "")
        model.isReadingContext = true
        enterPrompt()
        // The overlay goes up before the sheet comes down, so the dashed rectangle is never
        // missing for a frame between the two.
        fly(region, from: target)
        sheet?.close()
        contextTask = Task { [weak self, capture] in
            let image = await capture.image(windowID: target.windowID, region: region)
            let lines = if let image { await capture.recognizeLines(image) } else { [RobiRecognizedLine]() }
            guard !Task.isCancelled, let self else { return }
            // The region is in window-local points, so its lines are too, like the window's landmarks.
            self.model.context = RobiContext(kind: .region, text: lines.map(\.text).joined(separator: "\n"), image: image,
                                             landmarks: RobiLandmark.recognized(lines, in: region), windowSize: target.frame.size)
            self.model.isReadingContext = false
            self.suggestQuestions()
        }
    }

    /// The whole window as context: its accessibility text and landmarks, then its picture.
    private func takeWindow() {
        guard let target = tracker.target else { return }
        contextTask?.cancel()
        sheet?.close()
        model.context = RobiContext(kind: .window, text: "")
        model.isReadingContext = true
        enterPrompt()
        readWindow(target)
    }

    /// Reads the window's accessibility text and landmarks. A picture goes with them when Attach
    /// Picture is on, and as a fallback when the text is too thin to answer from (under 200
    /// characters); then the text Vision recognizes in the picture replaces the accessibility
    /// text if it found more, and its lines become the landmarks.
    private func readWindow(_ target: RobiWindowTarget) {
        let canCapture = CGPreflightScreenCaptureAccess()
        let attach = store.settings.attachWindowPicture
        model.canAttachPicture = canCapture
        contextTask = Task { [weak self, capture] in
            let reading = await RobiWindowText.read(processIdentifier: target.processIdentifier)
            var text = reading.text, landmarks = reading.landmarks, elements = reading.elements
            let isThin = text.count < 200
            var image: CGImage?
            if isThin || attach, canCapture, let picture = await capture.image(windowID: target.windowID) {
                image = picture
                if isThin {
                    let lines = await capture.recognizeLines(picture)
                    let recognized = lines.map(\.text).joined(separator: "\n")
                    if recognized.count > text.count {
                        text = recognized
                        landmarks = RobiLandmark.recognized(lines, in: CGRect(origin: .zero, size: target.frame.size))
                        // Recognized lines are numbered afresh and have no elements behind them.
                        elements = [:]
                    }
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.model.context = RobiContext(kind: .window, text: text, image: image, landmarks: landmarks, elements: elements,
                                             windowSize: target.frame.size, pictureIsFallback: isThin && image != nil)
            self.model.isReadingContext = false
            self.suggestQuestions()
            if text.isEmpty, image == nil, !canCapture { self.showNotice(.screenRecordingNeeded) }
        }
    }

    /// Flips Attach Picture from the prompt bar and applies it to the window already read: on
    /// takes the picture now, off drops one taken only because the switch was on. A fallback
    /// picture stays, since without it Robi would have almost nothing to read. An answer asked
    /// meanwhile waits for the picture, through `contextTask`.
    private func toggleWindowPicture() {
        store.settings.attachWindowPicture.toggle()
        let attach = store.settings.attachWindowPicture
        model.attachesWindowPicture = attach
        guard model.phase == .prompting, let target = tracker.target, let context = model.context, context.kind == .window else { return }
        if model.isReadingContext {
            // The read in progress decided before the switch flipped; read again with the new choice.
            contextTask?.cancel()
            return readWindow(target)
        }
        if attach, context.image == nil {
            guard CGPreflightScreenCaptureAccess() else {
                model.canAttachPicture = false
                return
            }
            model.isReadingContext = true
            contextTask = Task { [weak self, capture] in
                let picture = await capture.image(windowID: target.windowID)
                guard !Task.isCancelled, let self else { return }
                self.model.context?.image = picture
                self.model.isReadingContext = false
            }
        } else if !attach, context.image != nil, !context.pictureIsFallback {
            model.context?.image = nil
        }
    }

    private func enterPrompt() {
        model.prompt = ""
        model.request = ""
        model.answer = ""
        model.proposal = nil
        model.notice = nil
        model.toast = nil
        model.generatedSuggestions = []
        // Decided before the phase changes, so the panel grows once with room for the row.
        model.suggestsQuestions = store.settings.suggestQuestions && RobiSuggester.isAvailable
        setPhase(.prompting)
        panel?.allowsKey = true
        panel?.makeKey()
        if let kind = model.context?.kind { Analytics.track(.robiOpened(trigger: trigger, context: AnalyticsRobiContext(kind))) }
    }

    private func showNotice(_ notice: RobiNotice) {
        cancelSuggestions()
        if !model.phase.isBar { enterPrompt() }
        model.notice = notice
        setPhase(.thinking)
    }

    /// Asks Apple's on-device model for a few questions about the context the person just picked.
    ///
    /// Runs only in `.prompting`, once the context is read, so only after a click or the shortcut
    /// handed it to Robi; before that Robi reads nothing. It always runs on this Mac, whichever
    /// model answers, so the context never leaves the Mac for a suggestion. Failures, refusals
    /// and slow answers end silently: the built-in actions are still there.
    private func suggestQuestions() {
        cancelSuggestions()
        guard model.suggestsQuestions, model.phase == .prompting, let context = model.context,
              !context.text.isEmpty else { return }
        let applicationName = model.applicationName
        let trace = trace
        let builtIns = RobiIntent.actions(canReplace: model.canReplace).map { String(localized: $0.title) }
        suggestTask = Task { [weak self] in
            let questions = await RobiSuggester.questions(about: context, applicationName: applicationName,
                                                          excluding: builtIns, trace: trace)
            guard !Task.isCancelled, let self, self.model.phase == .prompting, !questions.isEmpty else { return }
            self.model.generatedSuggestions = questions
        }
    }

    private func cancelSuggestions() {
        suggestTask?.cancel()
        suggestTask = nil
    }

    // MARK: Answering

    private func ask(_ intent: RobiIntent, text: String, model override: RobiAnswerModel? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.phase == .prompting || model.notice == .claudeKeyMissing, !text.isEmpty, let target = tracker.target else { return }
        // The prompt is closing, so suggestions still being generated are no longer wanted.
        cancelSuggestions()
        // One answer at a time: a new question drops the one waiting on another window.
        dropParked()
        spotlight?.hide()
        model.request = text
        model.answer = ""
        model.proposal = nil
        model.notice = nil
        model.toast = nil
        model.isStopped = false
        setPhase(.thinking)
        let choice = override ?? store.settings.answerModel
        let claudeModel = store.settings.claudeModel
        model.answerModel = choice
        model.claudeModel = claudeModel
        let agentModel: RobiAgent.Model
        switch choice {
        case .onDevice:
            if let reason = RobiAgent.onDeviceUnavailableReason {
                model.notice = .onDeviceUnavailable(reason)
                return report(intent, outcome: .unavailable, started: Date())
            }
            agentModel = .onDevice
        case .claude:
            guard let key = store.claudeKey() else {
                pending = (intent, text)
                model.notice = .claudeKeyMissing
                return report(intent, outcome: .keyMissing, started: Date())
            }
            agentModel = .claude(claudeModel, key: key, effort: store.settings.claudeEffort)
        }
        pending = nil
        let started = Date()
        let acts = intent.canAct
        answerTask?.cancel()
        answerGeneration = nextGeneration()
        let generation = answerGeneration
        answering = (intent, started)
        let trace = trace
        answerTask = Task { [weak self, agent, contextTask, menuTask] in
            await contextTask?.value
            let catalog = acts ? await menuTask?.value ?? .empty : .empty
            // Read through the generation: the answer may have been set aside while it waited.
            guard !Task.isCancelled, let self, let exchange = self.exchange(generation) else { return }
            let request = RobiAgent.Request(intent: intent, text: text, context: exchange.context,
                                            applicationName: target.applicationName, menu: catalog, canAct: acts, trace: trace)
            var failure: Error?
            do {
                try await agent.answer(request, model: agentModel,
                                       // Each proposal holds every step so far. They hop to the main actor
                                       // separately, so a late, shorter one must not undo a newer one.
                                       propose: { [weak self] proposal in
                                           self?.receive(generation) { exchange in
                                               if proposal.steps.count > exchange.proposal?.steps.count ?? 0 { exchange.proposal = proposal }
                                           }
                                       },
                                       update: { [weak self] snapshot in self?.receive(generation) { $0.answer = snapshot } })
            } catch is CancellationError {
                return
            } catch {
                failure = error
            }
            guard !Task.isCancelled else { return }
            self.complete(generation, intent: intent, text: text, started: started, model: choice, claudeModel: claudeModel,
                          picture: request.context?.image != nil, failure: failure)
        }
    }

    /// The answer `generation` belongs to: the card on screen, or the answer set aside.
    private enum Destination { case card, parked }

    private func destination(of generation: Int) -> Destination? {
        if generation == answerGeneration { return .card }
        if parked?.generation == generation { return .parked }
        return nil
    }

    private func exchange(_ generation: Int) -> RobiExchange? {
        switch destination(of: generation) {
        case .card: return model.exchange
        case .parked: return parked?.exchange
        case nil: return nil
        }
    }

    /// Applies an update from answer `generation` wherever that answer is now. Updates from an
    /// answer that was stopped, dismissed or dropped go nowhere.
    private func receive(_ generation: Int, _ change: (inout RobiExchange) -> Void) {
        switch destination(of: generation) {
        case .card:
            var exchange = model.exchange
            change(&exchange)
            model.apply(exchange)
            if exchange.phase == .answered, model.phase != .answered { setPhase(.answered) }
        case .parked:
            change(&parked!.exchange)
        case nil:
            break
        }
    }

    /// The answer finished, failed, or came back empty, on screen or set aside.
    private func complete(_ generation: Int, intent: RobiIntent, text: String, started: Date,
                          model answerModel: RobiAnswerModel, claudeModel: RobiClaudeModel, picture: Bool, failure: Error?) {
        guard let destination = destination(of: generation) else { return }
        var outcome = AnalyticsRobiOutcome.answered
        var keyMissing = false
        receive(generation) { exchange in
            if let failure {
                outcome = .failed
                if case ClaudeError.missingCredential = failure {
                    keyMissing = true
                    exchange.notice = .claudeKeyMissing
                } else {
                    exchange.notice = .failed(RobiAgent.message(for: failure))
                }
            } else if exchange.answer.isEmpty, exchange.proposal == nil {
                exchange.notice = .failed(String(localized: .robiErrorEmpty))
            } else if exchange.proposal != nil {
                outcome = .proposed
            }
            exchange.phase = .answered
        }
        let waiting: (intent: RobiIntent, text: String)? = keyMissing ? (intent, text) : nil
        switch destination {
        case .card:
            answering = nil
            if keyMissing { pending = waiting }
        case .parked:
            parked?.task = nil
            parked?.answering = nil
            if keyMissing { parked?.pending = waiting }
            updateParkedBadge()
        }
        report(intent, outcome: outcome, started: started, model: (answerModel, claudeModel), picture: outcome != .failed && picture)
    }

    /// Stops the answer in progress and keeps whatever has arrived, with its actions enabled.
    ///
    /// Cancelling the task ends the model's response stream. On this Mac that ends generation.
    /// For Claude, ending the stream cancels the package's `URLSession` task and closes the
    /// streaming HTTP connection, which is the only way to stop a single Messages API request:
    /// the API has no cancel call for one.
    private func stopAnswer() {
        guard model.phase == .thinking, model.notice == nil, let task = answerTask else { return }
        task.cancel()
        answerTask = nil
        answerGeneration = nextGeneration()
        model.isStopped = true
        setPhase(.answered)
        if let answering { report(answering.intent, outcome: .stopped, started: answering.started) }
        answering = nil
    }

    private func report(_ intent: RobiIntent, outcome: AnalyticsRobiOutcome, started: Date,
                        model answered: (model: RobiAnswerModel, claude: RobiClaudeModel)? = nil, picture: Bool = false) {
        let (answerModel, claudeModel) = answered ?? (model.answerModel, model.claudeModel)
        Analytics.track(.robiAnswered(model: AnalyticsRobiModel(answerModel),
                                      claudeModel: answerModel == .claude ? AnalyticsRobiClaudeModel(claudeModel) : nil,
                                      intent: AnalyticsRobiIntent(intent),
                                      outcome: outcome, duration: Date().timeIntervalSince(started), picture: picture))
    }

    private func saveClaudeKey(_ key: String) {
        guard store.saveClaudeKey(key), let pending else { return }
        model.notice = nil
        model.phase = .prompting
        ask(pending.intent, text: pending.text)
    }

    private func answerPendingOnDevice() {
        guard let pending else { return }
        model.notice = nil
        model.phase = .prompting
        ask(pending.intent, text: pending.text, model: .onDevice)
    }

    // MARK: Putting the answer back

    private func copyAnswer() {
        RobiAppActions.copy(model.answerText)
        flash(.robiToastCopied)
        Analytics.track(.robiActionTaken(.copy))
    }

    private func replaceSelection() {
        guard let selection else { return }
        let result = RobiAppActions.replace(selection, with: model.answerText)
        switch result {
        case .replaced: flash(.robiToastReplaced)
        case .selectionChanged: flash(.robiToastSelectionChanged)
        case .failed: flash(.robiToastReplaceFailed)
        }
        guard result == .replaced else { return }
        Analytics.track(.robiActionTaken(.replace))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.dismiss() }
    }

    private func pasteAnswer() {
        guard let target = tracker.target else { return }
        let text = model.answerText
        dismiss()
        Analytics.track(.robiActionTaken(.paste))
        // Give the app its key window back before ⌘V arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            RobiAppActions.paste(text, into: target.processIdentifier)
        }
    }

    /// Runs the proposed steps in order, pausing between them so the app can react. The first
    /// step that cannot run stops the chain and the card says which; the rest are skipped. Robi
    /// closes a moment after every step ran, so the chip's check can be seen.
    ///
    /// A step may move focus, such as a command that opens a window. The run keeps going in the
    /// app it started in, and `leftWindow(_:)` waits for it before closing Robi.
    private func runProposal() {
        guard let proposal = model.proposal, model.phase == .answered, model.runState == nil,
              let target = tracker.target else { return }
        let pid = target.processIdentifier
        let elements = model.context?.elements ?? [:]
        let steps = proposal.steps
        spotlight?.hide()
        leftDuringRun = false
        runTask = Task { [weak self] in
            for (index, step) in steps.enumerated() {
                guard !Task.isCancelled, let self else { return }
                self.model.runState = .running(index: index)
                if index > 0 { try? await Task.sleep(for: RobiStepRunner.pause) }
                guard !Task.isCancelled else { return }
                guard await RobiStepRunner.run(step, processIdentifier: pid, elements: elements) else {
                    self.model.runState = .failed(index: index)
                    // The Run chip names the step a chain stopped at; one step only turns orange,
                    // so the toast says why.
                    if steps.count == 1 { self.flash(.robiToastStepMissing) }
                    self.reportRun(steps, completed: index)
                    if self.leftDuringRun { self.dismiss() }
                    return
                }
            }
            guard !Task.isCancelled, let self else { return }
            // The Run chip turns green with a check; no toast repeats it.
            self.model.runState = .done
            self.reportRun(steps, completed: steps.count)
            if !self.leftDuringRun { try? await Task.sleep(for: .milliseconds(700)) }
            guard !Task.isCancelled else { return }
            self.dismiss()
        }
    }

    /// Counts what ran, never what it was: no paths, labels or typed text.
    private func reportRun(_ steps: [RobiStep], completed: Int) {
        Analytics.track(.robiActionTaken(.runCommand))
        var counts = AnalyticsRobiStepCounts()
        for step in steps {
            switch step {
            case .menu: counts.menu += 1
            case .press: counts.press += 1
            case .toggle: counts.toggle += 1
            case .type: counts.type += 1
            }
        }
        Analytics.track(.robiStepsRun(counts, completed: completed))
    }

    /// Spotlights a landmark the answer referred to on the window it was read from, which is the
    /// pinned window while the card shows. Landmarks keep their place relative to the window's
    /// top-left corner; one that no longer falls inside the window, after a resize, says so.
    private func point(at id: Int) {
        guard model.phase.showsCard, let landmark = model.context?.landmark(id), let target = tracker.target else { return }
        let space = RobiScreenSpace.current
        let window = space.appKitRect(fromTopLeft: target.frame)
        let visible = landmark.frame.intersection(CGRect(origin: .zero, size: target.frame.size))
        guard !visible.isNull, visible.width >= 2, visible.height >= 2 else { return flash(.robiToastPointGone) }
        let spotlight = spotlight ?? RobiSpotlight()
        self.spotlight = spotlight
        spotlight.show(visible, over: window, below: panel, reduceMotion: model.reduceMotion,
                       reduceTransparency: model.reduceTransparency)
        if let panel {
            NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
                .announcement: String(localized: .robiPointAnnouncement(String(landmark.label.prefix(80)))),
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }
        Analytics.track(.robiActionTaken(.point))
    }

    private func flash(_ toast: LocalizedStringResource) {
        model.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.model.toast = nil
        }
    }

    private func openSettings() {
        prepareSettingsRoute()
        dismiss()
    }

    // MARK: Ending

    /// Closes the prompt bar and card and gives everything back: the keyboard, the target, and the
    /// app's accessibility mode.
    func dismiss() {
        endInteraction()
        guard running else { return }
        setPhase(hovering ? .awake : .idle)
        tracker.refresh()
    }

    private func endInteraction() {
        [contextTask, answerTask, toastTask, runTask].forEach { $0?.cancel() }
        cancelSuggestions()
        menuTask?.cancel()
        contextTask = nil; answerTask = nil; menuTask = nil; runTask = nil
        leftDuringRun = false
        answering = nil
        answerGeneration = nextGeneration()
        sheet?.close()
        spotlight?.hide()
        flight?.hide()
        calm()
        RobiWebAccessibility.restore(webChange)
        webChange = .none
        panel?.allowsKey = false
        if panel?.isKeyWindow == true { panel?.resignKey() }
        selection = nil
        pending = nil
        model.resetInteraction()
        tracker.isPinned = false
    }

    private func nextGeneration() -> Int {
        generations += 1
        return generations
    }

    // MARK: Setting an answer aside

    /// The pinned window lost focus or went away.
    ///
    /// A running step, such as a command that opens a window, may be what moved focus. The run
    /// then finishes in the app it started in, and Robi closes when it ends.
    private func leftWindow(_ departure: RobiWindowTracker.Departure) {
        if case .running = model.runState {
            leftDuringRun = true
            return
        }
        if departure == .switchedAway, canPark { park() } else { dismiss() }
    }

    /// An answer is worth keeping once it has been asked for and its context is read. Picking,
    /// typing, and notices end as before: nothing has been asked yet, or there is nothing to keep.
    /// Once its steps run, it is not kept either: a step that opens a window moves focus, and the
    /// steps must not be offered again on return.
    private var canPark: Bool {
        guard !model.isReadingContext, model.notice == nil, model.runState == nil else { return false }
        switch model.phase {
        case .thinking: return answerTask != nil
        case .answered: return !model.answer.isEmpty || model.proposal != nil
        default: return false
        }
    }

    /// Sets the card's answer aside on its window. A running answer keeps generating, and Robi
    /// follows focus with a dot on its face until the window comes back or the answer is dropped.
    private func park() {
        guard let target = tracker.target else { return dismiss() }
        dropParked()
        parked = RobiParked(windowID: target.windowID, applicationName: target.applicationName,
                            exchange: model.exchange, task: model.phase == .thinking ? answerTask : nil,
                            generation: answerGeneration, answering: answering, selection: selection, pending: pending)
        // Handed over, not cancelled: `endInteraction()` cancels what the controller still holds,
        // and the answer may still be waiting for the menu list.
        answerTask = nil
        menuTask = nil
        updateParkedBadge()
        parkedExpiry = Task { [weak self] in
            try? await Task.sleep(for: RobiParked.lifetime)
            guard !Task.isCancelled else { return }
            self?.dropParked()
        }
        dismiss()
    }

    /// The set-aside answer's window is focused again: its card comes back as it was, still
    /// streaming if the answer is not complete.
    private func restoreParked() {
        guard let parked else { return }
        self.parked = nil
        parkedExpiry?.cancel()
        parkedExpiry = nil
        model.parkedBadge = nil
        tracker.isPinned = true
        answerTask = parked.task
        answerGeneration = parked.generation
        answering = parked.answering
        selection = parked.selection
        pending = parked.pending
        model.restore(parked.exchange)
        setPhase(parked.exchange.phase)
    }

    /// Forgets the set-aside answer, cancelling it if it is still being written.
    private func dropParked() {
        parkedExpiry?.cancel()
        parkedExpiry = nil
        parked?.task?.cancel()
        parked = nil
        model.parkedBadge = nil
    }

    private func updateParkedBadge() {
        model.parkedBadge = parked.map { RobiParkedBadge(isWorking: $0.task != nil, applicationName: $0.applicationName) }
    }
}
