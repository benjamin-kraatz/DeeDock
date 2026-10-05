import Foundation

/// One answer to a survey question, in the form PostHog stores it.
nonisolated enum AnalyticsSurveyAnswer: Equatable, Sendable {
    /// A single-choice option, by its index in the author's (unshuffled) list.
    case choice(Int)
    /// Multiple-choice options, by index.
    case choices([Int])
    case rating(Int)
    case text(String)
}

/// Decides which question follows an answer, following PostHog's branching rules
/// (`getNextSurveyStep` in posthog-js), so a survey behaves the same here as on the web.
nonisolated enum AnalyticsSurveyFlow {
    enum Step: Equatable, Sendable {
        case question(Int)
        case end
    }

    /// The step after the question at `index`. A skipped optional question passes `nil`.
    /// A branch that points outside the survey ends it.
    static func step(after index: Int, in survey: AnalyticsSurvey, answer: AnalyticsSurveyAnswer?) -> Step {
        let next = index + 1 < survey.questions.count ? Step.question(index + 1) : .end
        guard survey.questions.indices.contains(index), let branching = survey.questions[index].branching else { return next }
        switch branching {
        case .next: return next
        case .end: return .end
        case let .question(target): return destination(.question(target), in: survey)
        case let .byResponse(values):
            guard let key = responseKey(for: answer, question: survey.questions[index]), let target = values[key] else { return next }
            return destination(target, in: survey)
        }
    }

    /// The `responseValues` key PostHog uses for an answer, if the question type branches.
    static func responseKey(for answer: AnalyticsSurveyAnswer?, question: AnalyticsSurvey.Question) -> String? {
        switch (question.kind, answer) {
        case let (.singleChoice, .choice(index)?): String(index)
        case let (.rating(rating), .rating(value)?): sentiment(value, scale: rating.scale)
        default: nil
        }
    }

    /// PostHog's rating buckets: thirds of the scale, with the NPS split on a 0–10 scale.
    static func sentiment(_ value: Int, scale: Int) -> String? {
        let negative: ClosedRange<Int>, neutral: ClosedRange<Int>
        switch scale {
        case 3: (negative, neutral) = (1...1, 2...2)
        case 5: (negative, neutral) = (1...2, 3...3)
        case 7: (negative, neutral) = (1...3, 4...4)
        case 10: (negative, neutral) = (0...6, 7...8)
        default: return nil
        }
        let names = scale == 10 ? ("detractors", "passives", "promoters") : ("negative", "neutral", "positive")
        if negative.contains(value) { return names.0 }
        if neutral.contains(value) { return names.1 }
        return names.2
    }

    private static func destination(_ target: AnalyticsSurvey.Destination, in survey: AnalyticsSurvey) -> Step {
        switch target {
        case .end: .end
        case let .question(index): survey.questions.indices.contains(index) ? .question(index) : .end
        }
    }
}
