import SwiftUI

/// "Found in dokk-web": the Finder suggestions inside the open panel, with Add per row and Add All.
struct VaporFoundInSection: View {
    let folderName: String
    let suggestions: [VaporSuggestion]
    let add: (VaporSuggestion) -> Void
    let addAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(.vaporFoundIn(folderName))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(.vaporAddAll, action: addAll)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
            ForEach(suggestions) { suggestion in
                HStack(spacing: 8) {
                    VaporFolderIcon(size: 20)
                    Text(verbatim: suggestion.name)
                        .font(.callout)
                        .lineLimit(1)
                    Text(VaporCopy.tag(suggestion.tag))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button(.vaporAdd) { add(suggestion) }
                        .controlSize(.small)
                        .accessibilityLabel(Text(.vaporAddSuggestion(suggestion.name)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.06))
    }
}

#if DEBUG
#Preview("Found in") {
    VaporFoundInSection(folderName: "dokk-web", suggestions: VaporPreviewData.suggestions, add: { _ in }, addAll: {})
        .frame(width: 340)
}
#endif
