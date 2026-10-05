import Foundation
import Testing
@testable import DeeDock

struct AnalyticsSurveyTests {
    /// The App Recommendations survey as `/api/surveys/` returned it on 2026-10-05, trimmed to
    /// the fields DOKK reads plus a few it must ignore.
    private static let json = #"""
    {
      "id": "01a10ae5-3be4-0000-cb04-a670009cadbf", "name": "App Recommendations Survey", "type": "api",
      "linked_flag_key": null, "targeting_flag_key": null, "conditions": null, "schedule": "recurring",
      "internal_targeting_flag_key": "survey-targeting-5ac84f2755-custom",
      "start_date": "2026-10-05T07:09:53.211000Z", "end_date": null, "current_iteration": 1,
      "current_iteration_start_date": "2026-10-05T07:09:53.211000Z", "enable_partial_responses": true,
      "appearance": { "displayThankYouMessage": true, "autoDisappear": true, "borderRadius": "10px",
                      "thankYouMessageHeader": "Vielen Dank für dein Feedback!" },
      "questions": [
        { "id": "q0", "type": "single_choice", "question": "Wie findest du die App-Vorschläge?",
          "choices": ["Ja", "Nein", "Kennst du Wayne?"], "skipSubmitButton": true, "scale": 5, "display": "emoji",
          "branching": { "type": "response_based", "responseValues": { "0": "end", "1": 1, "2": 1 } } },
        { "id": "q1", "type": "open", "question": "Dürfen wir wissen, was nicht gepasst hat?",
          "validation": [{ "type": "min_length", "value": 1 }, { "type": "max_length", "value": 666 }] },
        { "id": "q2", "type": "rating", "scale": 7, "display": "number", "optional": true, "isNpsQuestion": true,
          "question": "Wie Wayne ist es dir?", "lowerBoundLabel": "Wenig", "upperBoundLabel": "Sehr Wayne",
          "skipSubmitButton": true }
      ]
    }
    """#

    private static func survey(_ json: String = json) throws -> AnalyticsSurvey {
        try JSONDecoder().decode(AnalyticsSurvey.self, from: Data(json.utf8))
    }

    @Test("The live survey decodes, is supported, and runs from its start date")
    func decodesLiveSurvey() throws {
        let survey = try Self.survey()
        #expect(survey.isSupported)
        #expect(survey.partialResponses)
        #expect(survey.seenKey == "01a10ae5-3be4-0000-cb04-a670009cadbf/1")
        #expect(survey.appearance.closesAutomatically)
        #expect(survey.appearance.thankYouTitle == "Vielen Dank für dein Feedback!")
        let start = try Date("2026-10-05T07:09:53Z", strategy: .iso8601)
        #expect(!survey.isRunning(at: start.addingTimeInterval(-1)))
        #expect(survey.isRunning(at: start.addingTimeInterval(86400)))
        guard case let .rating(rating) = survey.questions[2].kind else { Issue.record("Expected a rating"); return }
        #expect(rating.values == 1...7)
        #expect(survey.questions[2].isOptional)
        guard case let .open(limits) = survey.questions[1].kind else { Issue.record("Expected an open question"); return }
        #expect(!limits.accepts("   "))
        #expect(limits.accepts(" passt "))
        #expect(!limits.accepts(String(repeating: "a", count: 667)))
    }

    @Test("A targeting flag or an unknown question type keeps a survey off screen", arguments: [
        (#""targeting_flag_key": null"#, #""targeting_flag_key": "beta""#),
        (#""type": "open""#, #""type": "link""#),
        (#""end_date": null"#, #""end_date": "2026-10-04T00:00:00Z""#),
    ])
    func rejectsWhatDOKKCannotHonor(original: String, replacement: String) throws {
        let survey = try Self.survey(Self.json.replacingOccurrences(of: original, with: replacement))
        let later = try Date("2026-10-06T00:00:00Z", strategy: .iso8601)
        #expect(!survey.isSupported || !survey.isRunning(at: later))
    }

    @Test("Branching follows the author's response values", arguments: [
        (0, AnalyticsSurveyFlow.Step.end),
        (1, .question(1)),
        (2, .question(1)),
    ])
    func choiceBranching(choice: Int, expected: AnalyticsSurveyFlow.Step) throws {
        #expect(AnalyticsSurveyFlow.step(after: 0, in: try Self.survey(), answer: .choice(choice)) == expected)
    }

    @Test("Questions without branching go on in order and the last one ends the survey")
    func linearSteps() throws {
        let survey = try Self.survey()
        #expect(AnalyticsSurveyFlow.step(after: 1, in: survey, answer: .text("x")) == .question(2))
        #expect(AnalyticsSurveyFlow.step(after: 2, in: survey, answer: nil) == .end)
    }

    @Test("Ratings fall into PostHog's sentiment buckets", arguments: [
        (1, 7, "negative"), (3, 7, "negative"), (4, 7, "neutral"), (5, 7, "positive"),
        (2, 5, "negative"), (3, 5, "neutral"), (4, 5, "positive"),
        (6, 10, "detractors"), (7, 10, "passives"), (9, 10, "promoters"),
    ])
    func ratingSentiment(value: Int, scale: Int, expected: String) {
        #expect(AnalyticsSurveyFlow.sentiment(value, scale: scale) == expected)
    }

    @Test("A sent event carries PostHog's response keys and the choice text")
    func sentPayload() throws {
        let survey = try Self.survey()
        let submission = UUID()
        let record = AnalyticsSurveyRecord.sent(survey, answers: ["q0": .choice(1), "q1": .text("  Zu viele Spiele \n"),
                                                                  "q2": .rating(6)],
                                                submissionID: submission, completed: true)
        #expect(record.name == "survey sent")
        #expect(record.properties["$survey_id"] as? String == survey.id)
        #expect(record.properties["$survey_iteration"] as? Int == 1)
        #expect(record.properties["$survey_response_q0"] as? String == "Nein")
        #expect(record.properties["$survey_response_q1"] as? String == "Zu viele Spiele")
        #expect(record.properties["$survey_response_q2"] as? String == "6")
        #expect(record.properties["$survey_completed"] as? Bool == true)
        #expect(record.properties["$survey_submission_id"] as? String == submission.uuidString)
        let questions = try #require(record.properties["$survey_questions"] as? [[String: Any]])
        #expect(questions.map { $0["id"] as? String } == ["q0", "q1", "q2"])
    }

    @Test("Dismissing after one answer reports a partial response")
    func dismissedPayload() throws {
        let record = AnalyticsSurveyRecord.dismissed(try Self.survey(), answers: ["q0": .choice(1)], submissionID: UUID())
        #expect(record.name == "survey dismissed")
        #expect(record.properties["$survey_partially_completed"] as? Bool == true)
        #expect(record.properties["$survey_response_q1"] == nil)
    }
}
