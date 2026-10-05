#if DEBUG
import SwiftUI

/// Debug-only switch for sending analytics from a development build, and tools for checking the
/// App Recommendations survey: random suggestions, so the launcher's Suggestions section exists
/// without learned history, and a button that puts the survey into it.
///
/// Debug builds send nothing by default. With the switch on, events go to the same project as
/// release builds, tagged `channel=debug`. Labels are developer copy and stay out of the
/// string catalog.
struct AnalyticsDebugMenu: View {
    let analytics: Analytics
    let suggestions: LauncherSuggestionsStore
    let survey: LauncherSuggestionSurvey

    var body: some View {
        Toggle(isOn: Binding(get: { analytics.debugSendingEnabled },
                             set: { analytics.debugSendingEnabled = $0 })) {
            Text(verbatim: "Debug: Send Analytics (channel=debug)")
        }
        Toggle(isOn: Binding(get: { suggestions.debugRandomSuggestions },
                             set: { suggestions.setDebugRandomSuggestions($0) })) {
            Text(verbatim: "Debug: Random App Suggestions")
        }
        // Appears below the suggested apps the next time App Launcher opens with an empty query.
        Button { Task { await survey.debugPresent() } } label: {
            Text(verbatim: "Debug: Show App Recommendations Survey")
        }
    }
}
#endif
