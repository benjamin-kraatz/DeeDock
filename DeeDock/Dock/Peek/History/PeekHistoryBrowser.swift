import SwiftUI

/// Searches the bounded text index locally; results are historical evidence, not live window links.
struct PeekHistoryBrowser: View {
    let history: PeekHistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(.peekHistoryTitle).font(.title2)
                Spacer()
                Button { dismiss() } label: { Text(.peekHistoryDone) }
                    .keyboardShortcut(.cancelAction)
            }
            TextField(text: $query) { Text(.peekHistorySearch) }
                .textFieldStyle(.roundedBorder)
            Text(.peekHistoryPrivacy).font(.caption).foregroundStyle(.secondary)
            if let error = history.error { Text(error).foregroundStyle(.red) }
            let results = history.results(for: query)
            if results.isEmpty {
                ContentUnavailableView {
                    Label { Text(.peekHistoryEmpty) } icon: { Image(systemName: "text.viewfinder") }
                } description: { Text(.peekHistoryEmptyHelp) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { entry in
                    PeekHistoryResultRow(entry: entry, disabled: history.busy) { history.delete(entry.id) }
                }
            }
            HStack {
                if history.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(role: .destructive) { confirmingClear = true } label: { Text(.peekHistoryClear) }
                    .disabled(history.busy)
            }
        }
        .padding(24)
        .frame(minWidth: 580, idealWidth: 700, minHeight: 440, idealHeight: 600)
        .confirmationDialog(Text(.peekHistoryClear), isPresented: $confirmingClear) {
            Button(role: .destructive) { history.delete() } label: { Text(.peekHistoryClear) }
        } message: { Text(.peekHistoryClearHelp) }
    }
}

private struct PeekHistoryResultRow: View {
    let entry: PeekHistoryEntry
    let disabled: Bool
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text(verbatim: entry.appName).font(.headline)
                    if !entry.windowTitle.isEmpty { Text(verbatim: entry.windowTitle).font(.subheadline) }
                    Text(entry.capturedAt, format: .dateTime).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive, action: delete) { Text(.peekHistoryDelete) }
                    .disabled(disabled)
            }
            Text(verbatim: entry.text).textSelection(.enabled)
        }
        .padding(.vertical, 8)
    }
}

#if DEBUG
#Preview("Recognized text") {
    PeekHistoryResultRow(entry: PeekHistoryEntry(id: UUID(), capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                               appName: "Notes", windowTitle: "Project notes",
                                               text: "Meet at the station at 16:30."), disabled: false, delete: {})
        .padding(24)
        .frame(width: 620)
}
#endif
