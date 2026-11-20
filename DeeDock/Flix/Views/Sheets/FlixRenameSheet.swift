import SwiftUI

/// Renames one file, prefilled with phase B2's suggestion when there is one.
struct FlixRenameSheet: View {
    let state: FlixPanelState
    let item: FlixItem
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        FlixSheetTitle(title: Text(.flixRenameTitle)) { state.sheet = nil }
        TextField(text: $name) { Text(verbatim: item.name) }
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit(commit)
            .onAppear {
                name = state.intelligence.annotation(for: item.id)?.renameSuggestion ?? item.path.map {
                    ($0 as NSString).lastPathComponent
                } ?? item.name
                focused = true
            }
        HStack {
            Spacer(minLength: 0)
            Button { state.sheet = nil } label: { Text(.flixCancel) }
            Button(action: commit) { Text(.flixRenameAction) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .controlSize(.small)
    }

    private func commit() {
        state.sheet = nil
        state.rename(item, to: name)
    }
}
