import SwiftUI

/// Renames one file, prefilled with phase B2's suggestion when there is one.
struct FlixRenameSheet: View {
    let state: FlixPanelState
    let item: FlixItem
    @State private var name = ""
    @FocusState private var focused: Bool

    private var suggestion: String? { state.intelligence.annotation(for: item.id)?.renameSuggestion }

    var body: some View {
        FlixSheetTitle(title: Text(.flixRenameTitle), intelligent: suggestion != nil) { state.sheet = nil }
        FlixSheetField(text: $name, prompt: Text(verbatim: item.name), focus: $focused, submit: commit)
            .onAppear {
                name = suggestion ?? item.path.map { ($0 as NSString).lastPathComponent } ?? item.name
                focused = true
            }
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button { state.sheet = nil } label: { Text(.flixCancel) }
                .buttonStyle(FlixCardButtonStyle())
            Button(action: commit) { Text(.flixRenameAction) }
                .buttonStyle(FlixCardButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func commit() {
        state.sheet = nil
        state.rename(item, to: name)
    }
}
