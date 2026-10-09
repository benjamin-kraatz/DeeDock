import SwiftUI

/// Notices above the Apps tab's results: action errors, unreadable stores or history, mixed-search
/// messages, Robi's answer, and the Easter egg. Renders nothing in the common case.
struct HubAppsStatusView: View {
    let launcher: LauncherState
    /// Asks the tab to confirm clearing launch history.
    let requestClearHistory: () -> Void

    var body: some View {
        if hasContent {
            notices
                .padding(.horizontal, HubAppsStyle.contentInsets.leading + 4)
                .padding(.top, 12)
        }
    }

    private var showsEngineUnavailable: Bool {
        launcher.query.isEmpty && !launcher.usesMixedResults && launcher.catalog.suggestions.isActive
            && !launcher.catalog.suggestions.engineBusy && launcher.catalog.suggestions.engineUnavailable
    }

    private var showsEasterEgg: Bool {
        launcher.query.lowercased().trimmingCharacters(in: .whitespaces) == "do a barrel roll"
    }

    private var hasContent: Bool {
        showsEngineUnavailable || launcher.search.actionError != nil || launcher.search.incompleteStores
            || (launcher.usesMixedResults && launcher.search.message != nil) || showsEasterEgg
            || launcher.error != nil || launcher.robiMessage != nil || launcher.history.unreadable
    }

    private var notices: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsEngineUnavailable {
                Text(.launcherSuggestionsEngineUnavailable).font(.caption).foregroundStyle(.secondary)
            }
            if let error = launcher.search.actionError {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if launcher.search.incompleteStores {
                Text(.unifiedStorageUnavailable).font(.caption).foregroundStyle(.secondary)
            }
            if launcher.usesMixedResults, let message = launcher.search.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if showsEasterEgg {
                HubAppsEasterEgg()
            }
            if let error = launcher.error {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if let message = launcher.robiMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            if launcher.history.unreadable {
                HStack {
                    Text(.launcherHistoryUnreadable).font(.caption).foregroundStyle(.secondary)
                    Button(action: requestClearHistory) { Text(.launcherClearHistory) }
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An explicit search phrase reveals a short, non-flashing motion, with a static Reduce Motion alternative.
private struct HubAppsEasterEgg: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rolled = false

    var body: some View {
        Label { Text(.launcherEasterEgg) } icon: {
            Image(systemName: "airplane").rotationEffect(.degrees(rolled && !reduceMotion ? 360 : 0))
        }
        .font(.headline).foregroundStyle(.tint)
        .onAppear { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) { rolled = true } }
    }
}
