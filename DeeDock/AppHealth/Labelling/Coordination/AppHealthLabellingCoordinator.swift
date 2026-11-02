import Foundation
import Observation

/// Runs labelling mode on top of `AppHealthController`: evaluates the suspicion rule after each tick, asks the
/// prompt policy, shows at most one prompt, runs the manual "Something's off right now…" picker, and writes each
/// question's `prompt`, backfill, and `label` records.
///
/// `DeeDockDelegate` owns it next to the controller, so the collector stays free of windows and can be tested
/// without them. Call `start()` before the controller starts and `stop()` after the controller stopped: the
/// controller's `willPause` runs during its stop, and this coordinator answers it by closing open questions as
/// interrupted while writes are still accepted.
///
/// It subscribes to `tickCompleted` only while `isLabellingActive` holds (collection and labelling both on), found
/// through Observation. Turning either switch off closes open questions as interrupted. Each question's timers live
/// in its `AppHealthLabelSession`; panels own their monitors and observers and remove them in `close()`.
@MainActor
final class AppHealthLabellingCoordinator {
    private let controller: AppHealthController
    private let dependencies: AppHealthLabellingDependencies
    private var started = false
    private var active = false
    /// Bumped by `stop()`, so a pending Observation callback from before cannot re-arm tracking.
    private var trackingGeneration = 0
    private var prompt: OpenQuestion?
    private var manual: OpenQuestion?
    private var picker: (any AppHealthPickerPresenting)?

    /// A question whose `prompt` record is written and whose `label` is not yet.
    private struct OpenQuestion {
        let id: UUID
        let app: String
        let window: DateInterval
        let shownAt: Date
        let source: AppHealthLabelSource
        let session: AppHealthLabelSession
        /// The prompt panel; nil for a manual question, which the picker hosts.
        let presenter: (any AppHealthPromptPresenting)?
    }

    init(controller: AppHealthController, dependencies: AppHealthLabellingDependencies) {
        self.controller = controller
        self.dependencies = dependencies
    }

    /// Whether an automatic prompt is on screen.
    var isPromptVisible: Bool { prompt != nil }

    /// Hooks into the controller and follows the labelling switches. Call once, before `controller.start()`.
    func start() {
        guard !started else { return }
        started = true
        controller.willPause = { [weak self] _ in self?.interruptQuestions() }
        trackActivation()
    }

    /// Closes every question and unhooks from the controller. Call after `controller.stop()`, which already
    /// recorded open questions as interrupted.
    func stop() {
        guard started else { return }
        started = false
        trackingGeneration &+= 1
        interruptQuestions()
        controller.willPause = nil
        controller.tickCompleted = nil
        active = false
    }

    // MARK: - Activation

    /// Reads `isLabellingActive` under Observation. Observation reports one change per registration, so each change
    /// registers the next read; `stop()` ends the chain through `trackingGeneration`.
    private func trackActivation() {
        let generation = trackingGeneration
        let isActive = withObservationTracking { controller.isLabellingActive } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.started, self.trackingGeneration == generation else { return }
                self.trackActivation()
            }
        }
        setActive(isActive)
    }

    private func setActive(_ value: Bool) {
        guard value != active else { return }
        active = value
        if value {
            controller.tickCompleted = { [weak self] report in self?.handleTick(report) }
        } else {
            controller.tickCompleted = nil
            interruptQuestions()
        }
    }

    // MARK: - Automatic prompts

    /// Runs after every written tick while labelling is active. The global caps are checked first, so a capped,
    /// paused, or busy tick evaluates no rule.
    func handleTick(_ report: AppHealthTickReport) {
        guard active else { return }
        let preferences = controller.labelling
        let context = AppHealthPromptPolicy.Context(
            now: dependencies.now(), questionVisible: prompt != nil || manual != nil || picker != nil,
            pausedUntil: preferences.pausedUntil, dontAsk: preferences.dontAsk, ownBundleID: dependencies.ownBundleID)
        let history = preferences.promptHistory
        guard AppHealthPromptPolicy.allowsAnyPrompt(history: history, context: context) else { return }

        var candidates: [AppHealthPromptCandidate] = []
        for (app, sample) in report.samples
        where AppHealthPromptPolicy.allowsAsking(about: app, history: history, context: context) {
            let samples = controller.history(for: app).map(\.sample)
            if let candidate = AppHealthPromptCandidate.evaluate(app: app, kind: sample.kind, history: samples,
                                                                 idleSeconds: report.idleSeconds) {
                candidates.append(candidate)
            }
        }
        guard let choice = AppHealthPromptPolicy.choose(from: candidates, history: history, context: context,
                                                        draw: dependencies.random) else { return }
        showPrompt(choice)
    }

    /// Writes the prompt and backfills its window, then puts it on screen and announces it.
    func showPrompt(_ candidate: AppHealthPromptCandidate) {
        guard active, prompt == nil, let anchor = controller.anchor(forBundleID: candidate.app) else { return }
        let shownAt = dependencies.now()
        let id = UUID()
        let window = AppHealthLabelWindow.prompt(shownAt: shownAt)
        controller.labelling.recordPrompt(app: candidate.app, trigger: candidate.trigger, at: shownAt)
        controller.writePrompt(AppHealthPromptRecord(id: id, app: candidate.app, kind: candidate.kind,
                                                     trigger: candidate.trigger, reasons: candidate.reasons,
                                                     anchor: anchor.kind), at: shownAt)
        controller.backfill(app: candidate.app, from: window.start, to: window.end)

        let display = dependencies.appDisplays([candidate.app])[candidate.app]
            ?? AppHealthAppDisplay(bundleID: candidate.app, name: candidate.app, icon: nil)
        let session = makeSession(id: id, app: candidate.app, display: display,
                                  reason: AppHealthReasonText.line(for: candidate), source: .prompt,
                                  window: window, shownAt: shownAt)
        session.menuCommand = { [weak self] command in self?.perform(command, about: candidate.app) }
        let app = candidate.app
        let presenter = dependencies.presentPrompt(session, anchor) { [weak controller] in
            controller?.anchor(forBundleID: app)
        }
        prompt = OpenQuestion(id: id, app: app, window: window, shownAt: shownAt, source: .prompt, session: session,
                              presenter: presenter)
        dependencies.announce(String(localized: .appHealthPromptAnnouncement(app: display.name)))
        session.start()
    }

    private func perform(_ command: AppHealthLabelSession.MenuCommand, about app: String) {
        switch command {
        case .dontAsk: controller.dontAsk(about: app)
        case .pauseToday: controller.pauseLabellingForToday()
        }
    }

    // MARK: - Manual labels

    /// "Something's off right now…": opens the picker over the latest tick's apps, busiest first. A second call
    /// brings the open picker forward.
    func showPicker() {
        guard active else { return }
        if let picker {
            picker.present()
            return
        }
        let samples = controller.lastTick?.samplesByCPU ?? []
        let displays = dependencies.appDisplays(samples.map(\.app))
        let entries = samples.map { sample in
            AppHealthPickerEntry(sample: sample, display: displays[sample.app]
                ?? AppHealthAppDisplay(bundleID: sample.app, name: sample.app, icon: nil))
        }
        let picker = dependencies.presentPicker(entries)
        picker.picked = { [weak self] entry in self?.manualPicked(entry) }
        picker.dismissed = { [weak self] in self?.pickerDismissed() }
        self.picker = picker
    }

    /// Writes the manual prompt and backfills its window at the moment of the pick, then shows the label choices.
    /// Manual labels bypass every cap and leave the policy's history untouched.
    private func manualPicked(_ entry: AppHealthPickerEntry) {
        guard active, manual == nil, let picker else { return }
        let pickedAt = dependencies.now()
        let id = UUID()
        let window = AppHealthLabelWindow.manual(pickedAt: pickedAt)
        controller.writePrompt(AppHealthPromptRecord(id: id, app: entry.sample.app, kind: entry.sample.kind,
                                                     trigger: .manual, reasons: [], anchor: .screen), at: pickedAt)
        controller.backfill(app: entry.sample.app, from: window.start, to: window.end)
        let session = makeSession(id: id, app: entry.sample.app, display: entry.display, reason: nil,
                                  source: .manual, window: window, shownAt: pickedAt)
        manual = OpenQuestion(id: id, app: entry.sample.app, window: window, shownAt: pickedAt, source: .manual,
                              session: session, presenter: nil)
        picker.showQuestion(session)
        session.start()
    }

    /// Escape or a focus change closed the picker. A picked app's question ends as dismissed; the list alone
    /// writes nothing.
    private func pickerDismissed() {
        if let manual {
            manual.session.dismiss()
        } else {
            closePicker()
        }
    }

    private func closePicker() {
        picker?.close()
        picker = nil
    }

    // MARK: - Questions

    private func makeSession(id: UUID, app: String, display: AppHealthAppDisplay, reason: String?,
                             source: AppHealthLabelSource, window: DateInterval, shownAt: Date) -> AppHealthLabelSession {
        let session = AppHealthLabelSession(app: display, reason: reason, source: source,
                                            timing: source == .prompt ? .prompt : .manual,
                                            now: dependencies.now, sleep: dependencies.sleep)
        session.labelled = { [weak self] result in
            self?.writeLabel(result, id: id, app: app, window: window, shownAt: shownAt, source: source)
        }
        session.finished = { [weak self] in self?.questionFinished(id) }
        return session
    }

    private func writeLabel(_ result: AppHealthLabelSession.Result, id: UUID, app: String, window: DateInterval,
                            shownAt: Date, source: AppHealthLabelSource) {
        controller.writeLabel(AppHealthLabelRecord(
            id: id, app: app, answer: result.answer, detail: result.detail, from: window.start, to: window.end,
            source: source, responseSeconds: max(0, result.answeredAt.timeIntervalSince(shownAt)),
            dismissed: result.dismissed, interrupted: result.interrupted))
        switch (source, result.answer) {
        case (.manual, .noAnswer): break
        case (.manual, _): Analytics.count(.appHealthManualLabel)
        // Closed by sleep, a switch, or quitting: neither answered nor ignored by the person.
        case (.prompt, .noAnswer) where result.interrupted: break
        case (.prompt, .noAnswer): Analytics.count(.appHealthPromptIgnored)
        case (.prompt, _): Analytics.count(.appHealthPromptAnswered)
        }
    }

    private func questionFinished(_ id: UUID) {
        if let prompt, prompt.id == id {
            self.prompt = nil
            prompt.presenter?.close()
        }
        if manual?.id == id {
            manual = nil
            closePicker()
        }
    }

    /// Closes every open question as interrupted, and the picker. Runs from `willPause` while writes are still
    /// accepted, when labelling turns off, and at `stop()`.
    private func interruptQuestions() {
        // Read first: interrupting finishes the question, which clears these properties.
        let open = [prompt?.session, manual?.session].compactMap { $0 }
        open.forEach { $0.interrupt() }
        closePicker()
    }
}
