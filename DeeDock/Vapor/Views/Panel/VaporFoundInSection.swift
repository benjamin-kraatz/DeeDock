import SwiftUI

/// "Found in dokk-web": the Finder suggestions inside the open panel, one row per suggestion
/// with Add, and Add All in the section's header.
struct VaporFoundInSection: View {
    let folderName: String
    let suggestions: [VaporSuggestion]
    let reduceMotion: Bool
    let add: (VaporSuggestion) -> Void
    let addAll: () -> Void

    /// Rows shown before the rest collapse into "N more".
    static let maxRows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(.vaporFoundIn(folderName))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Button(.vaporAddAll, action: addAll)
                    .buttonStyle(VaporPillButtonStyle(prominent: true))
            }
            .padding(EdgeInsets(top: 8, leading: 10, bottom: 4, trailing: 8))
            // A DerivedData folder can hold dozens of caches. Only the first few get rows, so the
            // panel never grows past the display and Hold to Delete stays reachable; Add All
            // still takes every one.
            ForEach(suggestions.prefix(Self.maxRows)) { suggestion in
                VaporFoundInRow(suggestion: suggestion) { add(suggestion) }
                    .transition(reduceMotion ? .opacity : .offset(x: 24).combined(with: .opacity))
            }
            if suggestions.count > Self.maxRows {
                Text(.vaporMoreSuggestions(suggestions.count - Self.maxRows))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(EdgeInsets(top: 2, leading: 44, bottom: 2, trailing: 8))
            }
        }
        .padding(.bottom, 6)
        .background(Color.accentColor.opacity(0.07), in: .rect(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.5))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : VaporMotion.rowEnter, value: suggestions.map(\.id))
    }
}

/// One suggestion: icon, name, tag and Add.
private struct VaporFoundInRow: View {
    let suggestion: VaporSuggestion
    let add: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            VaporFolderIcon(size: 22)
                .frame(width: 26)
            Text(verbatim: suggestion.name)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            VaporTagChip(classification: .known(suggestion.tag))
            Spacer(minLength: 4)
            Button(.vaporAdd, action: add)
                .buttonStyle(VaporPillButtonStyle())
                .accessibilityLabel(Text(.vaporAddSuggestion(suggestion.name)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(hovered ? VaporStyle.selection : .clear, in: .rect(cornerRadius: 10, style: .continuous))
        .onHover { hovered = $0 }
    }
}

#if DEBUG
#Preview("Found in") {
    VaporFoundInSection(folderName: "dokk-web", suggestions: VaporPreviewData.suggestions, reduceMotion: false,
                        add: { _ in }, addAll: {})
        .frame(width: VaporPanelView.width)
        .padding(.vertical)
}
#endif
