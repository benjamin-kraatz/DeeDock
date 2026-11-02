import Foundation
import Observation

/// One open labelling question, from the moment it appears until its label is written and it can go away.
///
/// The prompt panel and the manual picker both host it. Views read `phase`, `expiry`, and `highlighted`, and call
/// the intent methods; the coordinator receives exactly one `labelled` result and then one `finished` call, and
/// closes whatever hosts the question.
///
/// Phases run `asking → followUp → thanks`, with every phase able to end early. At most one timer runs at a time
/// (`timer`): the expiry while asking, the follow-up timeout, or the thank-you pause. Every transition cancels the
/// previous one, and `finish()` cancels whatever is left, so no timer outlives the question.
@MainActor @Observable
final class AppHealthLabelSession {
    enum Phase: Equatable {
        /// Expected / Misbehaving / Not sure.
        case asking
        /// After Misbehaving: Spinning / Memory growing / Frozen / Draining battery, or Skip.
        case followUp
        /// The label is written; a short confirmation before the question goes away.
        case thanks
    }

    /// One control the keyboard can reach.
    enum Choice: Hashable {
        case answer(AppHealthAnswer)
        case detail(AppHealthAnswerDetail)
        case skip
    }

    /// What the expiry indicator shows.
    struct Expiry: Equatable {
        /// Share of the time left, from 1 (just shown) to 0 (expired).
        var fraction: Double
        /// Seconds until the fraction reaches 0 while the countdown runs; nil while it is paused.
        var secondsLeft: TimeInterval?
    }

    /// The label to write. `answeredAt` gives `responseSeconds`.
    struct Result: Equatable {
        var answer: AppHealthAnswer
        var detail: AppHealthAnswerDetail?
        var answeredAt: Date
        var dismissed = false
        var interrupted = false
    }

    /// How long each phase waits.
    struct Timing: Equatable {
        /// Asking expires after this long without the pointer over the question; nil never expires.
        var expiry: Duration?
        /// The follow-up is skipped after this long.
        var followUp: Duration
        /// The thank-you confirmation shows this long.
        var thanks: Duration

        /// An automatic prompt: 60 s to answer, 20 s for the follow-up.
        static let prompt = Timing(expiry: .seconds(60), followUp: .seconds(20), thanks: .seconds(1.2))
        /// A manual label: the person asked for it, so asking never expires.
        static let manual = Timing(expiry: nil, followUp: .seconds(20), thanks: .seconds(1.2))
    }

    /// The commands of the prompt's "…" menu.
    enum MenuCommand: Equatable {
        case dontAsk, pauseToday
    }

    let app: AppHealthAppDisplay
    /// The localized line saying what was noticed; nil for manual labels.
    let reason: String?
    let source: AppHealthLabelSource
    private(set) var phase: Phase = .asking
    /// Nil when the question never expires or no longer can.
    private(set) var expiry: Expiry?
    /// The control the keyboard would activate. Nil until the host has keyboard focus.
    private(set) var highlighted: Choice?

    /// Called once with the label to write.
    @ObservationIgnored var labelled: ((Result) -> Void)?
    /// Called once when the question can go away.
    @ObservationIgnored var finished: (() -> Void)?
    /// Called for a "…" menu command, after the question has ended as dismissed.
    @ObservationIgnored var menuCommand: ((MenuCommand) -> Void)?

    @ObservationIgnored private let timing: Timing
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var expiryLeft: TimeInterval
    /// When the running countdown last resumed; nil while paused or not counting.
    @ObservationIgnored private var expiryResumedAt: Date?
    @ObservationIgnored private var engaged = false
    @ObservationIgnored private var keyboardActive = false
    @ObservationIgnored private var misbehavingAt: Date?
    @ObservationIgnored private var resultSent = false
    @ObservationIgnored private var done = false

    /// - Parameter sleep: Waits for a timer. Throws when cancelled.
    init(app: AppHealthAppDisplay, reason: String?, source: AppHealthLabelSource, timing: Timing,
         now: @escaping @MainActor () -> Date, sleep: @escaping @Sendable (Duration) async throws -> Void) {
        self.app = app
        self.reason = reason
        self.source = source
        self.timing = timing
        self.now = now
        self.sleep = sleep
        expiryLeft = timing.expiry.map(Self.seconds) ?? 0
        if timing.expiry != nil { expiry = Expiry(fraction: 1, secondsLeft: nil) }
    }

    isolated deinit {
        timer?.cancel()
    }

    /// The controls of the current phase, in keyboard order.
    var choices: [Choice] {
        switch phase {
        case .asking: [.answer(.expected), .answer(.misbehaving), .answer(.notSure)]
        case .followUp: AppHealthAnswerDetail.allCases.map(Choice.detail) + [.skip]
        case .thanks: []
        }
    }

    /// Starts the expiry countdown, if this question expires.
    func start() {
        resumeExpiry()
    }

    // MARK: - Intents

    /// Expected, Misbehaving, or Not sure. Misbehaving moves to the follow-up; the others write the label.
    func answer(_ answer: AppHealthAnswer) {
        guard phase == .asking, !done else { return }
        switch answer {
        case .misbehaving:
            misbehavingAt = now()
            stopExpiry()
            phase = .followUp
            highlighted = keyboardActive ? choices.first : nil
            schedule(after: timing.followUp) { $0.followUpTimedOut() }
        case .noAnswer:
            dismiss()
        case .expected, .notSure:
            send(Result(answer: answer, answeredAt: now()))
            showThanks()
        }
    }

    /// A follow-up chip, or nil for Skip. Writes Misbehaving with that detail.
    func chooseDetail(_ detail: AppHealthAnswerDetail?) {
        guard phase == .followUp, !done else { return }
        send(Result(answer: .misbehaving, detail: detail, answeredAt: misbehavingAt ?? now()))
        showThanks()
    }

    /// The close button or Escape. Unanswered: `noAnswer`, dismissed. In the follow-up: Misbehaving without a
    /// detail, since the person already answered.
    func dismiss() {
        guard !done else { return }
        switch phase {
        case .asking: send(Result(answer: .noAnswer, answeredAt: now(), dismissed: true))
        case .followUp: send(Result(answer: .misbehaving, answeredAt: misbehavingAt ?? now()))
        case .thanks: break
        }
        finish()
    }

    /// Sleep, turning labelling or collection off, or quitting closed the question. Writes what is known so far,
    /// marked interrupted, and ends without a confirmation.
    func interrupt() {
        guard !done else { return }
        switch phase {
        case .asking: send(Result(answer: .noAnswer, answeredAt: now(), interrupted: true))
        case .followUp: send(Result(answer: .misbehaving, answeredAt: misbehavingAt ?? now(), interrupted: true))
        case .thanks: break
        }
        finish()
    }

    /// A "…" menu command: ends the question as dismissed, then hands the command on.
    func perform(_ command: MenuCommand) {
        guard !done else { return }
        dismiss()
        menuCommand?(command)
    }

    /// Activates a control, as a click on it would.
    func activate(_ choice: Choice) {
        switch choice {
        case .answer(let answer): self.answer(answer)
        case .detail(let detail): chooseDetail(detail)
        case .skip: chooseDetail(nil)
        }
    }

    // MARK: - Host state

    /// The pointer is over the question, or its host has keyboard focus. Pauses the expiry while true.
    func setEngaged(_ value: Bool) {
        guard value != engaged else { return }
        engaged = value
        if value { pauseExpiry() } else { resumeExpiry() }
    }

    /// The host gained or lost keyboard focus. Highlights the first control while focused.
    func setKeyboardActive(_ value: Bool) {
        keyboardActive = value
        highlighted = value ? (highlighted ?? choices.first) : nil
    }

    /// Moves the keyboard highlight through the current controls, wrapping at either end.
    func moveHighlight(by offset: Int) {
        let choices = choices
        guard !choices.isEmpty else { return }
        let current = highlighted.flatMap { choices.firstIndex(of: $0) } ?? (offset > 0 ? -1 : 0)
        let next = (current + offset) % choices.count
        highlighted = choices[next < 0 ? next + choices.count : next]
    }

    /// Activates the highlighted control. Returns false when nothing is highlighted.
    @discardableResult
    func activateHighlighted() -> Bool {
        guard let highlighted, choices.contains(highlighted) else { return false }
        activate(highlighted)
        return true
    }

    // MARK: - Timers

    private func expire() {
        guard phase == .asking, !done else { return }
        send(Result(answer: .noAnswer, answeredAt: now()))
        finish()
    }

    private func followUpTimedOut() {
        guard phase == .followUp, !done else { return }
        send(Result(answer: .misbehaving, answeredAt: misbehavingAt ?? now()))
        finish()
    }

    private func showThanks() {
        phase = .thanks
        highlighted = nil
        schedule(after: timing.thanks) { $0.finish() }
    }

    /// Starts or continues the countdown with the time that is left.
    private func resumeExpiry() {
        guard let total = timing.expiry.map(Self.seconds), phase == .asking, !done, !engaged,
              expiryResumedAt == nil else { return }
        expiryResumedAt = now()
        expiry = Expiry(fraction: expiryLeft / total, secondsLeft: expiryLeft)
        schedule(after: .seconds(expiryLeft)) { $0.expire() }
    }

    /// Stops the countdown, keeping the time that is left.
    private func pauseExpiry() {
        guard let total = timing.expiry.map(Self.seconds), let resumedAt = expiryResumedAt else { return }
        timer?.cancel()
        timer = nil
        expiryResumedAt = nil
        expiryLeft = max(0, expiryLeft - now().timeIntervalSince(resumedAt))
        expiry = Expiry(fraction: expiryLeft / total, secondsLeft: nil)
    }

    /// Ends the countdown for good once the person answered.
    private func stopExpiry() {
        timer?.cancel()
        timer = nil
        expiryResumedAt = nil
        expiry = nil
    }

    /// Replaces the running timer. The task inherits the main actor and holds the session weakly, so a released
    /// session never fires.
    private func schedule(after delay: Duration, _ action: @escaping (AppHealthLabelSession) -> Void) {
        timer?.cancel()
        let sleep = sleep
        timer = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            action(self)
        }
    }

    // MARK: - Ending

    private func send(_ result: Result) {
        guard !resultSent else { return }
        resultSent = true
        labelled?(result)
    }

    private func finish() {
        guard !done else { return }
        done = true
        timer?.cancel()
        timer = nil
        expiryResumedAt = nil
        let finished = finished
        self.finished = nil
        labelled = nil
        finished?()
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
