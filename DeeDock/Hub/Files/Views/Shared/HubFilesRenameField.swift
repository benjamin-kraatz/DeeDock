import SwiftUI

/// The inline rename field. Opens with the name selected up to its extension; Return commits,
/// Escape cancels, and moving focus away commits.
struct HubFilesRenameField: View {
    let model: HubFilesModel
    @Bindable var pane: HubFilesPane
    /// Folders select the whole name; files stop before the extension, like Finder.
    var isDirectory = false
    var alignment: TextAlignment = .leading
    /// Fixed field width; nil fills the available width (narrow column-view items).
    var width: CGFloat? = 180

    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool
    @State private var selection: TextSelection?

    var body: some View {
        TextField(String(localized: .hubFilesRenamePlaceholder), text: $pane.renameDraft, selection: $selection)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .multilineTextAlignment(alignment)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .background(scheme == .dark ? Color(white: 0.12) : .white, in: .rect(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 2).padding(-2) }
            .focused($focused)
            .onSubmit { model.commitRename(in: pane) }
            .onExitCommand { model.cancelRename(in: pane) }
            .onAppear {
                let draft = pane.renameDraft
                let stem = isDirectory ? draft : HubFileNaming.split(draft).stem
                selection = TextSelection(range: draft.startIndex..<draft.index(draft.startIndex, offsetBy: stem.count))
                focused = true
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused, pane.renamingURL != nil { model.commitRename(in: pane) }
            }
            .accessibilityLabel(Text(.hubFilesMenuRename))
    }
}
