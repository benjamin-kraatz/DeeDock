#if DEBUG
import SwiftUI

/// The App Recommendations survey as PostHog serves it. Previews send nothing: the controller
/// has no ``Analytics`` and the store keeps nothing on disk.
@MainActor
private enum LauncherSurveyPreviewData {
    static let json = #"""
    {
      "id": "01a10ae5-3be4-0000-cb04-a670009cadbf", "name": "App Recommendations Survey", "type": "api",
      "linked_flag_key": null, "targeting_flag_key": null, "conditions": null,
      "start_date": "2026-10-05T07:09:53.211000Z", "end_date": null, "current_iteration": 1,
      "current_iteration_start_date": "2026-10-05T07:09:53.211000Z", "enable_partial_responses": true,
      "appearance": {
        "displayThankYouMessage": true, "autoDisappear": false,
        "thankYouMessageHeader": "Vielen Dank für dein Feedback!",
        "thankYouMessageDescription": "Es hilft uns sehr, DOKK für dich zu verbessern.",
        "thankYouMessageCloseButtonText": "Geil!"
      },
      "questions": [
        { "id": "q0", "type": "single_choice", "question": "Wie findest du die App-Vorschläge?",
          "description": "Werden dir Apps vorgeschlagen, die nützlich sind?",
          "choices": ["Ja", "Nein", "Kennst du Wayne?"], "skipSubmitButton": true, "buttonText": "Submit",
          "branching": { "type": "response_based", "responseValues": { "0": "end", "1": 1, "2": 1 } } },
        { "id": "q1", "type": "open", "question": "Dürfen wir wissen, was nicht gepasst hat?",
          "description": "Um Vorschläge für dich zu verbessern, wäre es hilfreich, wenn du uns einen kurzen Einblick geben würdest, was an den Vorschlägen nicht gepasst hat.",
          "buttonText": "Feedback geben",
          "validation": [{ "type": "min_length", "value": 1 }, { "type": "max_length", "value": 666 }] },
        { "id": "q2", "type": "rating", "scale": 7, "display": "number", "optional": true,
          "question": "Wie Wayne ist es dir?", "description": "Das hilft uns, es ungefähr einzuschätzen",
          "lowerBoundLabel": "Wenig", "upperBoundLabel": "Sehr Wayne", "skipSubmitButton": true, "buttonText": "Senden" }
      ]
    }
    """#

    static var survey: AnalyticsSurvey {
        // A preview fixture: a decoding failure should be loud.
        try! JSONDecoder().decode(AnalyticsSurvey.self, from: Data(json.utf8))
    }

    /// A controller on the given question, or in the given closing state.
    static func controller(question: Int = 0, phase: LauncherSuggestionSurvey.Phase? = nil) -> LauncherSuggestionSurvey {
        let controller = LauncherSuggestionSurvey(store: LauncherSuggestionsStore(directory: nil, defaults: nil),
                                                  analytics: nil, survey: survey)
        if question >= 1 { controller.answer(.choice(1), toQuestionAt: 0) }
        if question >= 2 { controller.answer(.text("Zu viele Spiele"), toQuestionAt: 1) }
        switch phase {
        case .thanks?: controller.answer(.choice(0), toQuestionAt: 0)
        case .dismissed?: controller.dismiss()
        default: break
        }
        return controller
    }
}

/// Stands in for the launcher's glass so the card's wash and edge read as they do in place.
private struct LauncherSurveyPreviewFrame<Content: View>: View {
    var width: CGFloat = 720
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(24)
            .frame(width: width)
            .background(.regularMaterial)
    }
}

#Preview("First question: choices that answer on click") {
    LauncherSurveyPreviewFrame { LauncherSurveyCard(survey: LauncherSurveyPreviewData.controller()) }
}

#Preview("Open answer after “Nein”") {
    LauncherSurveyPreviewFrame { LauncherSurveyCard(survey: LauncherSurveyPreviewData.controller(question: 1)) }
}

#Preview("Optional 7-point rating, dark") {
    LauncherSurveyPreviewFrame { LauncherSurveyCard(survey: LauncherSurveyPreviewData.controller(question: 2)) }
        .preferredColorScheme(.dark)
}

#Preview("Thank-you message") {
    LauncherSurveyPreviewFrame { LauncherSurveyCard(survey: LauncherSurveyPreviewData.controller(phase: .thanks)) }
}

#Preview("Dismissed, English, narrow") {
    LauncherSurveyPreviewFrame(width: 420) {
        LauncherSurveyCard(survey: LauncherSurveyPreviewData.controller(phase: .dismissed))
    }
        .environment(\.locale, Locale(identifier: "en"))
}
#endif
