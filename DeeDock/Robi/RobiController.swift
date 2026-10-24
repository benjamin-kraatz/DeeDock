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
    @ObservationIgnored private var panelSize = CGSize.zero
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var pointerMonitors: [Any] = []
    @ObservationIgnored private var blinkTimer: Timer?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var shrinkTask: Task<Void, Never>?
    @ObservationIgnored private var presenceTask: Task<Void, Never>?
    @ObservationIgnored private var tintTask: Task<Void, Never>?
    @ObservationIgnored private var contextTask: Task<Void, Never>?
    @ObservationIgnored private var menuTask: Task<[String], Never>?
    @ObservationIgnored private var answerTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var selection: RobiSelection?
    @ObservationIgnored private var webChange: RobiWebAccessibility.Change = .none
    /// A question waiting for an API key to be entered in the card.
    @ObservationIgnored private var pending: (intent: RobiIntent, text: String)?
    @ObservationIgnored private var hovering = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var running = false
    @ObservationIgnored private var trigger: AnalyticsTrigger = .click

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
        model.claudeEffort = settings.claudeEffort
        tracker.excludedBundleIdentifiers = Set(settings.excludedBundleIdentifiers)
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
        tracker.leftWhilePinned = { [weak self] in self?.dismiss() }
        tracker.start()
        Task { [capture] in await capture.prewarm() }
    }

    private func halt() {
        guard running else { return }
        running = false
        endInteraction()
        tracker.stop()
        tracker.targetChanged = nil
        tracker.frameChanged = nil
        tracker.leftWhilePinned = nil
        stopPointerTracking()
        [sleepTask, shrinkTask, presenceTask, tintTask].forEach { $0?.cancel() }
        model.isPresent = false
        model.phase = .idle
        panel?.orderOut(nil)
    }

    private func makePanel() -> RobiPanel {
        var actions = RobiActions()
        actions.tapFace = { [weak self] in self?.summon(.click) }
        actions.submit = { [weak self] text in self?.ask(.custom, text: text) }
        actions.suggest = { [weak self] intent in self?.ask(intent, text: String(localized: intent.title)) }
        actions.copy = { [weak self] in self?.copyAnswer() }
        actions.replace = { [weak self] in self?.replaceSelection() }
        actions.paste = { [weak self] in self?.pasteAnswer() }
        actions.runProposal = { [weak self] in self?.runProposal() }
        actions.saveClaudeKey = { [weak self] key in self?.saveClaudeKey(key) }
        actions.answerOnDevice = { [weak self] in self?.answerPendingOnDevice() }
        actions.openSettings = { [weak self] in self?.openSettings() }
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
        let frame = RobiLayout.panelFrame(window: window, placement: placement, size: panelSize, display: display)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        sheet?.move(over: window)
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
        let centre = RobiLayout.anchorX(window: window, display: space.display(for: window)) - window.minX
        tintTask = Task { [weak self, capture] in
            guard let color = await capture.tint(windowID: target.windowID, footprint: (centre - half)...(centre + half)),
                  !Task.isCancelled, let self, self.tracker.target?.windowID == target.windowID else { return }
            let rgb = color.usingColorSpace(.sRGB) ?? color
            let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
            self.model.tint = Color(nsColor: rgb)
            self.model.tintIsDark = luminance < 0.5
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
                guard !Task.isCancelled, let self, self.model.phase == .awake, !self.hovering else { return }
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
        eyes.isBlinking = false
        eyes.pupil = CGSize(width: 0, height: 2)
    }

    private func blink() {
        eyes.isBlinking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.eyes.isBlinking = false }
    }

    /// Points the pupils at the pointer, reaching full deflection 140 pt away.
    private func updatePupils() {
        guard let panel, !model.reduceMotion else { return }
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let faceX = model.phase.isBar ? frame.minX + RobiMetrics.sideMargin + RobiMetrics.flare + 7 + 20 : frame.midX
        let tabTop = model.placement == .above ? frame.maxY - RobiMetrics.shadowMargin : frame.maxY
        let dx = mouse.x - faceX, dy = mouse.y - (tabTop - RobiMetrics.tabHeight / 2)
        let distance = max(1, hypot(dx, dy))
        let reach = min(1, distance / 140)
        let next = CGSize(width: dx / distance * 2.6 * reach, height: -dy / distance * 2.2 * reach)
        if abs(next.width - eyes.pupil.width) > 0.05 || abs(next.height - eyes.pupil.height) > 0.05 { eyes.pupil = next }
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
    private func summon(_ trigger: AnalyticsTrigger) {
        guard running else { return }
        switch model.phase {
        case .idle, .awake:
            guard tracker.target != nil else { return NSSound.beep() }
            begin(trigger)
        case .selecting: takeWindow()
        case .prompting, .thinking, .answered: dismiss()
        }
    }

    /// Text selected in the app becomes the context straight away. Without a selection, Robi
    /// enters selection mode. Electron and Chromium apps get their web tree switched on first and
    /// are read once more a moment later, since their selection is invisible to AX until then.
    private func begin(_ trigger: AnalyticsTrigger) {
        guard let target = tracker.target else { return }
        self.trigger = trigger
        tracker.isPinned = true
        didUse()
        let pid = target.processIdentifier
        menuTask = Task { await RobiMenuCommands.list(processIdentifier: pid) }
        if let found = RobiSelectionReader.selection(processIdentifier: pid) { return useSelection(found) }
        if let application = NSRunningApplication(processIdentifier: pid) { webChange = RobiWebAccessibility.enable(for: application) }
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

    private func takeRegion(_ region: CGRect) {
        guard let target = tracker.target else { return }
        contextTask?.cancel()
        sheet?.close()
        guard CGPreflightScreenCaptureAccess() else { return showNotice(.screenRecordingNeeded) }
        model.context = RobiContext(kind: .region, text: "")
        model.isReadingContext = true
        enterPrompt()
        contextTask = Task { [weak self, capture] in
            let image = await capture.image(windowID: target.windowID, region: region)
            let text = if let image { await capture.recognizeText(image) } else { "" }
            guard !Task.isCancelled, let self else { return }
            self.model.context = RobiContext(kind: .region, text: text, image: image)
            self.model.isReadingContext = false
        }
    }

    /// The window's accessibility text when it has some, otherwise its picture and the text in it.
    private func takeWindow() {
        guard let target = tracker.target else { return }
        contextTask?.cancel()
        sheet?.close()
        model.context = RobiContext(kind: .window, text: "")
        model.isReadingContext = true
        enterPrompt()
        let canCapture = CGPreflightScreenCaptureAccess()
        contextTask = Task { [weak self, capture] in
            var text = await RobiWindowText.read(processIdentifier: target.processIdentifier)
            var image: CGImage?
            if text.count < 200, canCapture, let picture = await capture.image(windowID: target.windowID) {
                image = picture
                let recognized = await capture.recognizeText(picture)
                if recognized.count > text.count { text = recognized }
            }
            guard !Task.isCancelled, let self else { return }
            self.model.context = RobiContext(kind: .window, text: text, image: image)
            self.model.isReadingContext = false
            if text.isEmpty, image == nil, !canCapture { self.showNotice(.screenRecordingNeeded) }
        }
    }

    private func enterPrompt() {
        model.prompt = ""
        model.request = ""
        model.answer = ""
        model.proposal = nil
        model.notice = nil
        model.toast = nil
        setPhase(.prompting)
        panel?.allowsKey = true
        panel?.makeKey()
        if let kind = model.context?.kind { Analytics.track(.robiOpened(trigger: trigger, context: AnalyticsRobiContext(kind))) }
    }

    private func showNotice(_ notice: RobiNotice) {
        if !model.phase.isBar { enterPrompt() }
        model.notice = notice
        setPhase(.thinking)
    }

    // MARK: Answering

    private func ask(_ intent: RobiIntent, text: String, model override: RobiAnswerModel? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.phase == .prompting || model.notice == .claudeKeyMissing, !text.isEmpty, let target = tracker.target else { return }
        model.request = text
        model.answer = ""
        model.proposal = nil
        model.notice = nil
        model.toast = nil
        setPhase(.thinking)
        let choice = override ?? store.settings.answerModel
        model.answerModel = choice
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
            agentModel = .claude(key: key, effort: store.settings.claudeEffort)
        }
        pending = nil
        let started = Date()
        let acts = intent == .doIt || intent == .custom
        answerTask?.cancel()
        answerTask = Task { [weak self, agent, contextTask, menuTask] in
            await contextTask?.value
            let commands = acts ? await menuTask?.value ?? [] : []
            guard !Task.isCancelled, let self else { return }
            let request = RobiAgent.Request(intent: intent, text: text, context: self.model.context,
                                            applicationName: target.applicationName, menuCommands: commands)
            do {
                try await agent.answer(request, model: agentModel,
                                       propose: { [weak self] path in self?.model.proposal = RobiProposal(path: path) },
                                       update: { [weak self] snapshot in self?.model.answer = snapshot })
                guard !Task.isCancelled else { return }
                if self.model.answer.isEmpty, self.model.proposal == nil {
                    self.model.notice = .failed(String(localized: .robiErrorEmpty))
                }
                self.setPhase(.answered)
                self.report(intent, outcome: self.model.proposal == nil ? .answered : .proposed, started: started, picture: request.context?.image != nil)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if case ClaudeError.missingCredential = error {
                    self.pending = (intent, text)
                    self.model.notice = .claudeKeyMissing
                } else {
                    self.model.notice = .failed(RobiAgent.message(for: error))
                }
                self.setPhase(.answered)
                self.report(intent, outcome: .failed, started: started)
            }
        }
    }

    private func report(_ intent: RobiIntent, outcome: AnalyticsRobiOutcome, started: Date, picture: Bool = false) {
        Analytics.track(.robiAnswered(model: AnalyticsRobiModel(model.answerModel), intent: AnalyticsRobiIntent(intent),
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
        RobiAppActions.copy(model.answer)
        flash(.robiToastCopied)
        Analytics.track(.robiActionTaken(.copy))
    }

    private func replaceSelection() {
        guard let selection else { return }
        let result = RobiAppActions.replace(selection, with: model.answer)
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
        let text = model.answer
        dismiss()
        Analytics.track(.robiActionTaken(.paste))
        // Give the app its key window back before ⌘V arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            RobiAppActions.paste(text, into: target.processIdentifier)
        }
    }

    private func runProposal() {
        guard let proposal = model.proposal, let target = tracker.target else { return }
        let pressed = RobiMenuCommands.press(processIdentifier: target.processIdentifier, path: proposal.path)
        flash(pressed ? .robiToastDone : .robiToastCommandMissing)
        guard pressed else { return }
        Analytics.track(.robiActionTaken(.runCommand))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.dismiss() }
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
        [contextTask, answerTask, toastTask].forEach { $0?.cancel() }
        menuTask?.cancel()
        contextTask = nil; answerTask = nil; menuTask = nil
        sheet?.close()
        RobiWebAccessibility.restore(webChange)
        webChange = .none
        panel?.allowsKey = false
        if panel?.isKeyWindow == true { panel?.resignKey() }
        selection = nil
        pending = nil
        model.resetInteraction()
        tracker.isPinned = false
    }
}
