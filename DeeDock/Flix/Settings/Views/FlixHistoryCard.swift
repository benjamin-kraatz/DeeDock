import SwiftUI

/// Forgets the activity history. The library (Favorites, Smart Filters) and the files stay.
struct FlixHistoryCard: View {
    let count: Int
    let clear: () -> Void
    @State private var confirming = false

    var body: some View {
        SettingsCard(footnote: .flixSettingsHistoryHelp) {
            SettingsRow(title: .flixSettingsHistory, subtitle: .flixSettingsHistoryCount(count)) {
                Button(role: .destructive) { confirming = true } label: { Text(.flixSettingsClearHistory) }
                    .controlSize(.small)
                    .disabled(count == 0)
            }
        }
        .confirmationDialog(Text(.flixSettingsClearHistoryConfirm), isPresented: $confirming) {
            Button(role: .destructive, action: clear) { Text(.flixSettingsClearHistory) }
        } message: { Text(.flixSettingsClearHistoryMessage) }
    }
}
