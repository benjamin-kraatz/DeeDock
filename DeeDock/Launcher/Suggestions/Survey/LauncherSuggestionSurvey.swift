import Foundation
import Observation

/// Runs the "App Recommendations Survey" inside the launcher's Suggestions section.
///
/// The survey is authored in PostHog as an API survey; ``AnalyticsSurvey`` describes it and
/// this controller walks a person through it, following the author's branching, and reports
/// `survey shown`, `survey sent`, and `survey dismissed`.
///
/// It appears only when the suggestion store would ask for feedback anyway (suggestions active,
/// feedback questions on, enough impressions, the 30-day pause over) and analytics are being
/// collected, because an answer that cannot be sent is not worth asking for. Each survey
/// iteration is offered once: answering or dismissing it is remembered across launches.
///
/// One instance is shared by every display's launcher, so an answer begun on one display
/// continues on another.
@MainActor @Observable
final class LauncherSuggestionSurvey {
    /// The PostHog survey this controller presents.
    static let surveyID = "01a10ae5-3be4-0000-cb04-a670009cadbf"

    enum Phase: Hashable {
        /// Nothing on screen.
        case closed
        /// The question at this index of ``AnalyticsSurvey/questions`` is on screen.
        case asking(Int)
        /// The thank-you message after the last answer.
        case thanks
        /// A short confirmation after dismissal that offers to stop asking altogether.
        case dismissed
    }

    private(set) var survey: AnalyticsSurvey?
    private(set) var phase: Phase = .closed
    /// Keyed by question ID. A skipped optional question has no entry.
    private(set) var answers: [String: AnalyticsSurveyAnswer] = [:]
    /// Display order of each shuffled choice question, fixed for one submission.
    private(set) var choiceOrders: [String: [Int]] = [:]
    /// Questions answered or skipped so far, in order.
    private(set) var answeredCount = 0

    @ObservationIgnored private let store: LauncherSuggestionsStore
    @ObservationIgnored private let analytics: Analytics?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var seen: Set<String>
    @ObservationIgnored private var submissionID = UUID()
    @ObservationIgnored private var announced = false
    @ObservationIgnored private var loading = false
#if DEBUG
    /// Set by ``debugPresent()`` to show the survey without waiting for the store's prompt window.
    private var forced = false
#else
    private let forced = false
#endif
    private static let seenKey = "launcher.suggestions.survey.seen.v1"

    /// - Parameters:
    ///   - analytics: fetches the definition and receives the events. Nil never offers a survey.
    ///   - defaults: remembers answered iterations. Nil keeps that in memory, for previews and tests.
    ///   - survey: starts with this survey on screen, for previews.
    init(store: LauncherSuggestionsStore, analytics: Analytics?, defaults: UserDefaults? = nil,
         survey: AnalyticsSurvey? = nil) {
        self.store = store
        self.analytics = analytics
        self.defaults = defaults
        seen = Set(defaults?.stringArray(forKey: Self.seenKey) ?? [])
        if let survey { begin(survey) }
    }

    /// Whether the Suggestions section shows the survey card.
    var isPresented: Bool {
        switch phase {
        case .closed: false
        case .thanks, .dismissed: true
        // Once begun, the card stays until finished even if the store's prompt window moves on.
        case .asking: forced || (store.isActive && store.promptsEnabled && (store.shouldPrompt || answeredCount > 0))
        }
    }

    /// The question on screen, with its index.
    var currentQuestion: (index: Int, question: AnalyticsSurvey.Question)? {
        guard case let .asking(index) = phase, let survey, survey.questions.indices.contains(index) else { return nil }
        return (index, survey.questions[index])
    }

    /// Questions answered so far and the most the survey can still ask. Branching can end it sooner.
    var progress: (completed: Int, total: Int) {
        guard let survey, case let .asking(index) = phase else { return (0, 0) }
        return (answeredCount, answeredCount + survey.questions.count - index)
    }

    /// Loads the survey when the store is ready to ask. Cheap when there is nothing to do; the
    /// definition request is cached by ``AnalyticsSurveyCatalog``.
    func prepare() async {
        guard phase == .closed, !loading, store.shouldPrompt, let analytics else { return }
        loading = true
        defer { loading = false }
        guard let loaded = await analytics.activeSurvey(id: Self.surveyID), !seen.contains(loaded.seenKey),
              phase == .closed, store.shouldPrompt else { return }
        begin(loaded)
    }

#if DEBUG
    /// Shows the survey in the launcher now, ignoring the prompt window, earlier answers, and
    /// whether analytics are sending. Events reach PostHog only with debug sending switched on.
    func debugPresent() async {
        guard let analytics, let loaded = await analytics.debugSurvey(id: Self.surveyID) else {
            print("DOKK debug: App Recommendations Survey unavailable (no credentials, request failed, or not running)")
            return
        }
        forced = true
        begin(loaded)
    }
#endif

    /// Sends `survey shown` the first time the card is on screen for this submission.
    func presented() {
        guard let survey, case .asking = phase, !announced else { return }
        announced = true
        analytics?.captureSurvey(.shown(survey))
    }

    /// Records an answer, or a skip with `nil`, and moves to the question the author's
    /// branching chooses. Ignored unless the question at `index` is on screen.
    func answer(_ answer: AnalyticsSurveyAnswer?, toQuestionAt index: Int) {
        guard let survey, phase == .asking(index) else { return }
        answers[survey.questions[index].id] = answer
        answeredCount += 1
        switch AnalyticsSurveyFlow.step(after: index, in: survey, answer: answer) {
        case let .question(next):
            phase = .asking(next)
            // PostHog merges these by submission ID, so an answer survives a later dismissal.
            if survey.partialResponses, answer != nil { send(survey, completed: false) }
        case .end:
            send(survey, completed: true)
            finish(survey, then: survey.appearance.showsThankYou ? .thanks : .closed)
        }
    }

    /// Closes the survey unfinished and reports what was answered.
    func dismiss() {
        guard let survey, case .asking = phase else { return }
        analytics?.captureSurvey(.dismissed(survey, answers: answers, submissionID: submissionID))
        finish(survey, then: .dismissed)
    }

    /// Turns off feedback questions, the same switch as in Settings › Suggestions & History.
    func stopAsking() {
        store.suppressPrompts()
        phase = .closed
    }

    /// Removes the thank-you message or the dismissal confirmation.
    func close() {
        guard phase == .thanks || phase == .dismissed else { return }
        phase = .closed
    }

    private func begin(_ survey: AnalyticsSurvey) {
        self.survey = survey
        answers = [:]
        answeredCount = 0
        submissionID = UUID()
        announced = false
        choiceOrders = [:]
        for question in survey.questions {
            switch question.kind {
            case let .singleChoice(choices), let .multipleChoice(choices):
                let order = Array(choices.options.indices)
                choiceOrders[question.id] = choices.shuffles ? order.shuffled() : order
            default: break
            }
        }
        phase = .asking(0)
    }

    private func send(_ survey: AnalyticsSurvey, completed: Bool) {
        analytics?.captureSurvey(.sent(survey, answers: answers, submissionID: submissionID, completed: completed))
    }

    private func finish(_ survey: AnalyticsSurvey, then next: Phase) {
#if DEBUG
        forced = false
#endif
        seen.insert(survey.seenKey)
        defaults?.set(seen.sorted(), forKey: Self.seenKey)
        // Starts the store's 30-day pause before the next feedback question of any kind.
        store.answerPrompt(nil)
        phase = next
    }
}
