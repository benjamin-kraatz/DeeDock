import SwiftUI

/// Uses the same app controls as browsing, with separate selection identities and contextual feedback.
/// The App Recommendations survey appears below the apps when the store is ready to ask.
struct LauncherSuggestedSection: View {
    let state: LauncherState
    let columns: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var survey: LauncherSuggestionSurvey { state.catalog.suggestionSurvey }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.launcherSuggestionsSectionTitle)
                .font(.headline).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader).padding(.leading, 12)
            if state.layout == .grid {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: max(1, columns)), spacing: 0) {
                    applications
                }
            } else {
                LazyVStack(spacing: 0) { applications }
            }
            if survey.isPresented {
                LauncherSurveyCard(survey: survey) { state.surveyTextFocused = $0 }
                    .padding(.top, 8)
                    .transition(LauncherSurveyMotion(reduceMotion: reduceMotion).card)
            }
        }
        .animation(LauncherSurveyMotion(reduceMotion: reduceMotion).morph, value: survey.isPresented)
        .task(id: state.catalog.suggestions.shouldPrompt) { await survey.prepare() }
        .onAppear {
            state.recordSuggestionImpression()
            if state.contentVisible { survey.presented() }
        }
        .onChange(of: state.contentVisible) { _, visible in
            state.recordSuggestionImpression()
            if visible { survey.presented() }
        }
        .onChange(of: survey.isPresented) { _, presented in
            if presented, state.contentVisible { survey.presented() }
        }
        .onChange(of: state.suggestedApplications.map(\.id)) { _, _ in state.recordSuggestionImpression() }
    }

    private var applications: some View {
        ForEach(state.suggestedApplications) { application in
            LauncherResultButton(application: application, state: state, isSuggestion: true)
                .id(LauncherBrowseID.suggested(application.id))
        }
    }
}

struct LauncherSuggestionActions: View {
    let application: LauncherApplication
    let state: LauncherState

    var body: some View {
        Button { state.suggestionFeedback(application, kind: .useful) } label: {
            Label { Text(.launcherSuggestionsUseful) } icon: { Image(systemName: "hand.thumbsup") }
        }
        Button { state.suggestionFeedback(application, kind: .notNow) } label: {
            Label { Text(.launcherSuggestionsNotNow) } icon: { Image(systemName: "hand.thumbsdown") }
        }
        Button { state.catalog.suggestions.exclude(appID: application.id) } label: {
            Label { Text(.launcherSuggestionsExclude) } icon: { Image(systemName: "nosign") }
        }
    }
}
