import SwiftUI

/// App-wide consent and privacy controls for the single shared suggestion recorder.
struct LauncherSuggestionsSettingsView: View {
    let store: LauncherSuggestionsStore
    /// Names come from the current app library, never from stored learning history.
    var applications: [LauncherApplication] = []
    @State private var confirmingReset = false

    private var exclusions: [(id: String, name: String)] {
        store.excludedIDs.map { id in
            (id: id, name: applications.first(where: { $0.id == id })?.reference.name ?? id)
        }.sorted { lhs, rhs in
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
            SettingsCard(title: .launcherSuggestionsSettingsTitle,
                         footnote: .launcherSuggestionsPrivacy) {
                SettingsToggleRow(title: .launcherSuggestionsEnabled,
                                  subtitle: .launcherSuggestionsEnabledHelp,
                                  isOn: Binding(get: { store.enabled }, set: store.setEnabled))
                    .disabled(store.storageUnavailable && !store.enabled)
                SettingsToggleRow(title: .launcherSuggestionsPaused,
                                  subtitle: .launcherSuggestionsPausedHelp,
                                  isOn: Binding(get: { store.paused }, set: store.setPaused))
                    .disabled(!store.enabled || store.storageUnavailable)
            }
            if store.storageUnavailable {
                Text(.launcherSuggestionsStorageUnavailable)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsCard(title: .launcherSuggestionsFeedbackTitle,
                         footnote: .launcherSuggestionsPromptsHelp) {
                SettingsToggleRow(title: .launcherSuggestionsPromptsEnabled,
                                  isOn: Binding(get: { store.promptsEnabled }, set: store.setPromptsEnabled))
            }
            SettingsCard(title: .launcherSuggestionsExcludedTitle,
                         footnote: .launcherSuggestionsExcludedHelp) {
                if exclusions.isEmpty {
                    SettingsStackedRow {
                        Text(.launcherSuggestionsExcludedEmpty)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ForEach(exclusions, id: \.id) { app in
                        SettingsStackedRow {
                            HStack {
                                Text(verbatim: app.name)
                                    .textSelection(.enabled)
                                Spacer(minLength: SettingsMetrics.controlSpacing)
                                Button(.launcherSuggestionsInclude) { store.include(appID: app.id) }
                                    .accessibilityLabel(Text(.launcherSuggestionsIncludeApp(app.name)))
                            }
                        }
                    }
                }
            }
            SettingsCard(title: .launcherSuggestionsDataTitle,
                         footnote: .launcherSuggestionsResetHelp) {
                SettingsActionRow {
                    Button(.launcherSuggestionsReset, role: .destructive) { confirmingReset = true }
                }
            }
        }
        .alert(String(localized: .launcherSuggestionsResetTitle), isPresented: $confirmingReset) {
            Button(.launcherSuggestionsReset, role: .destructive) { store.reset() }
            Button(.actionCancel, role: .cancel) { }
        } message: {
            Text(.launcherSuggestionsResetConfirmation)
        }
    }
}

#if DEBUG
#Preview("Suggestions off") {
    @Previewable @State var store = LauncherSuggestionsStore(directory: nil, defaults: nil)
    ScrollView {
        LauncherSuggestionsSettingsView(store: store)
            .padding(24)
    }
    .frame(width: 600, height: 680)
}

#Preview("Suggestions German dark") {
    @Previewable @State var store = LauncherSuggestionsStore(directory: nil, defaults: nil)
    ScrollView {
        LauncherSuggestionsSettingsView(store: store)
            .padding(24)
    }
    .environment(\.locale, Locale(identifier: "de"))
    .preferredColorScheme(.dark)
    .frame(width: 520, height: 680)
}
#endif
