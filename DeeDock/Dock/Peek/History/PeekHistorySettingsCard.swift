import SwiftUI

/// Collection is a separate opt-in from Screen Recording. Browsing and deletion stay available while paused.
struct PeekHistorySettingsCard: View {
    let history: PeekHistoryStore
    @State private var browsing = false
    @State private var confirmingClear = false

    var body: some View {
        SettingsCard(title: .peekHistoryTitle, footnote: .peekHistoryPrivacy) {
            SettingsToggleRow(title: .peekHistoryEnable,
                              isOn: Binding(get: { history.enabled }, set: history.setEnabled))
                .disabled(history.busy || history.unreadable)
            SettingsStackedRow {
                Text(.peekHistoryCaptureHelp).font(.caption).foregroundStyle(.secondary)
                if let error = history.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            SettingsActionRow {
                Button { browsing = true } label: { Text(.peekHistoryBrowse) }
                Button(role: .destructive) { confirmingClear = true } label: { Text(.peekHistoryClear) }
                    .disabled(history.busy)
            }
        }
        .sheet(isPresented: $browsing) { PeekHistoryBrowser(history: history) }
        .confirmationDialog(Text(.peekHistoryClear), isPresented: $confirmingClear) {
            Button(role: .destructive) { history.delete() } label: { Text(.peekHistoryClear) }
        } message: { Text(.peekHistoryClearHelp) }
    }
}

#if DEBUG
#Preview("Peek history, off") {
    PeekHistorySettingsCard(history: PeekHistoryStore(repository: nil))
        .padding(24)
        .frame(width: 620)
}
#endif
