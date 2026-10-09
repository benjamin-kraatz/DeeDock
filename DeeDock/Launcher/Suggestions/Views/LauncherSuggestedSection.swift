import SwiftUI

/// Up to three suggested apps as cards (mockup `.sugg`), with their own selection identities and
/// feedback actions. The App Recommendations survey appears below the cards when the store is
/// ready to ask.
struct LauncherSuggestedSection: View {
    let state: LauncherState
    /// When the Apps tab appeared; cards created right after it run the staggered entrance.
    var appearedAt: Date = .distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var survey: LauncherSuggestionSurvey { state.catalog.suggestionSurvey }
    private var applications: [LauncherApplication] { state.suggestedApplications }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HubAppsSectionHeader(title: Text(.launcherSuggestionsSectionTitle))
            // Always three equal columns, so one or two suggestions keep the card width.
            HStack(alignment: .top, spacing: HubAppsStyle.suggestionSpacing) {
                ForEach(0..<3, id: \.self) { index in
                    if index < applications.count {
                        LauncherSuggestionCard(application: applications[index], state: state)
                            .id(LauncherBrowseID.suggested(applications[index].id))
                            .hubAppsEntrance(index: index, stagger: HubAppsStyle.cardStagger,
                                             appearedAt: appearedAt)
                    } else {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                            .accessibilityHidden(true)
                    }
                }
            }
            if survey.isPresented {
                LauncherSurveyCard(survey: survey) { state.surveyTextFocused = $0 }
                    .padding(.top, 14)
                    .transition(LauncherSurveyMotion(reduceMotion: reduceMotion).card)
            }
        }
        .animation(LauncherSurveyMotion(reduceMotion: reduceMotion).morph, value: survey.isPresented)
        .task(id: state.catalog.suggestions.shouldPrompt) { await survey.prepare() }
        .onAppear {
            state.recordSuggestionImpression()
            if state.isActive { survey.presented() }
        }
        .onChange(of: state.isActive) { _, active in
            state.recordSuggestionImpression()
            if active { survey.presented() }
        }
        .onChange(of: survey.isPresented) { _, presented in
            if presented, state.isActive { survey.presented() }
        }
        .onChange(of: state.suggestedApplications.map(\.id)) { _, _ in state.recordSuggestionImpression() }
    }
}

/// Feedback for one suggestion, shared by the card's context menu and accessibility actions.
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
