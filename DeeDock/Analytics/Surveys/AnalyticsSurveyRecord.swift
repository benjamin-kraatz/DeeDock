import Foundation

/// A PostHog survey event: `survey shown`, `survey sent`, or `survey dismissed`.
///
/// Like ``AIObservabilityRecord`` this bypasses the ``AnalyticsValue`` allowlist, because a
/// survey response is text by nature: the chosen option, and whatever a person typed into an
/// open question. Only ``Analytics/captureSurvey(_:)`` sends it, behind the same consent gate as
/// every other event. The property names and value shapes match posthog-ios 3.89.0
/// (`PostHogSurveyIntegration.sendSurvey…Event`) so PostHog's survey results read them.
nonisolated struct AnalyticsSurveyRecord: @unchecked Sendable {
    let name: String
    let properties: [String: Any]

    static func shown(_ survey: AnalyticsSurvey) -> Self {
        Self(name: "survey shown", properties: base(survey))
    }

    /// - Parameters:
    ///   - answers: keyed by question ID. Questions without an answer are listed without one.
    ///   - completed: false for an intermediate partial response.
    static func sent(_ survey: AnalyticsSurvey, answers: [String: AnalyticsSurveyAnswer],
                     submissionID: UUID, completed: Bool) -> Self {
        var properties = base(survey).merging(responses(survey, answers)) { _, new in new }
        properties["$survey_completed"] = completed
        properties["$survey_submission_id"] = submissionID.uuidString
        return Self(name: "survey sent", properties: properties)
    }

    static func dismissed(_ survey: AnalyticsSurvey, answers: [String: AnalyticsSurveyAnswer], submissionID: UUID) -> Self {
        var properties = base(survey).merging(responses(survey, answers)) { _, new in new }
        properties["$survey_partially_completed"] = !answers.isEmpty
        properties["$survey_submission_id"] = submissionID.uuidString
        return Self(name: "survey dismissed", properties: properties)
    }

    private static func base(_ survey: AnalyticsSurvey) -> [String: Any] {
        var properties: [String: Any] = ["$survey_id": survey.id, "$survey_name": survey.name]
        properties["$survey_iteration"] = survey.iteration
        properties["$survey_iteration_start_date"] = survey.iterationStartDate
        return properties
    }

    /// `$survey_response_<question id>` per answer, plus `$survey_questions` listing every question.
    private static func responses(_ survey: AnalyticsSurvey, _ answers: [String: AnalyticsSurveyAnswer]) -> [String: Any] {
        var properties: [String: Any] = [:]
        var questions: [[String: Any]] = []
        for question in survey.questions {
            var entry: [String: Any] = ["id": question.id, "question": question.title]
            if let answer = answers[question.id], let value = value(answer, for: question) {
                entry["response"] = value
                properties["$survey_response_\(question.id)"] = value
            }
            questions.append(entry)
        }
        properties["$survey_questions"] = questions
        return properties
    }

    /// Choices are stored by their text, ratings as a numeric string, as PostHog expects.
    private static func value(_ answer: AnalyticsSurveyAnswer, for question: AnalyticsSurvey.Question) -> Any? {
        switch (answer, question.kind) {
        case let (.choice(index), .singleChoice(choices)):
            choices.options.indices.contains(index) ? choices.options[index] : nil
        case let (.choices(indexes), .multipleChoice(choices)):
            indexes.filter(choices.options.indices.contains).map { choices.options[$0] }
        case let (.rating(value), .rating): String(value)
        case let (.text(text), .open): text.trimmingCharacters(in: .whitespacesAndNewlines)
        default: nil
        }
    }
}
