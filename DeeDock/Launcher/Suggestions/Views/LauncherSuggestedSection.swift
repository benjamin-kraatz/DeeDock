import SwiftUI

/// Uses the same app controls as browsing, with separate selection identities and contextual feedback.
struct LauncherSuggestedSection: View {
    let state: LauncherState
    let columns: Int

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
            if state.catalog.suggestions.shouldPrompt {
                LauncherSuggestionPrompt(store: state.catalog.suggestions)
            }
        }
        .onAppear { state.recordSuggestionImpression() }
        .onChange(of: state.contentVisible) { _, _ in state.recordSuggestionImpression() }
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

/// Aggregate responses do not label individual applications as good or bad targets.
private struct LauncherSuggestionPrompt: View {
    let store: LauncherSuggestionsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.launcherSuggestionsPrompt).font(.callout)
            ViewThatFits(in: .horizontal) {
                HStack { answers; preferences }
                VStack(alignment: .leading) {
                    HStack { answers }
                    HStack { preferences }
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
    }

    private var answers: some View {
        Group {
            Button(.launcherSuggestionsYes) { store.answerPrompt(true) }
            Button(.launcherSuggestionsNo) { store.answerPrompt(false) }
        }
    }

    private var preferences: some View {
        Group {
            Button(.launcherSuggestionsDismiss) { store.answerPrompt(nil) }
            Button(.launcherSuggestionsDontAsk) { store.suppressPrompts() }
        }
    }
}
