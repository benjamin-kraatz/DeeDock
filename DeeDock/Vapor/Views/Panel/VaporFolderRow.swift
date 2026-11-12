import SwiftUI

/// One folder: icon, name, tag chip, parent path, size and file count, and × on hover.
struct VaporFolderRow: View {
    let folder: VaporFolder
    let home: URL
    let reduceMotion: Bool
    let remove: () -> Void

    @State private var hovered = false

    /// Size and file count, then the reason the last delete left this folder, if any: the row
    /// ignores its children for VoiceOver, so the visible failure line must be repeated here.
    private var accessibilityValue: String {
        let size = VaporRowSize.accessibilityValue(folder.measurement)
        guard let failure = folder.failure else { return size }
        return "\(size), \(String(localized: VaporCopy.failure(failure)))"
    }

    var body: some View {
        HStack(spacing: 10) {
            VaporFolderIcon(size: 30)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: folder.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                    VaporTagChip(classification: folder.classification)
                }
                Text(verbatim: folder.parentPath(home: home))
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(VaporStyle.faint)
                    .lineLimit(1)
                    .truncationMode(.head)
                if let failure = folder.failure {
                    Text(VaporCopy.failure(failure))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(VaporStyle.danger)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            VaporRowSize(measurement: folder.measurement, reduceMotion: reduceMotion)
            VaporCloseButton(label: .vaporRemove, action: remove)
                .opacity(hovered ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 8))
        .background(hovered ? VaporStyle.selection : .clear, in: .rect(cornerRadius: 13, style: .continuous))
        .contentShape(.rect(cornerRadius: 13, style: .continuous))
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.vaporRowAccessibility(folder.name, String(localized: VaporCopy.tag(folder.classification)),
                                                        folder.parentPath(home: home))))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityAction(named: Text(.vaporRemove), remove)
    }
}

/// The macOS folder icon for one folder. Uses the generic folder icon so previews and rows
/// never read live workspace state for a custom icon.
struct VaporFolderIcon: View {
    var size: CGFloat

    var body: some View {
        VaporFolderSprite.image
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Rows") {
    VStack(spacing: 0) {
        ForEach(VaporPreviewData.mixed + VaporPreviewData.calculating + VaporPreviewData.failed) { folder in
            VaporFolderRow(folder: folder, home: VaporPreviewData.home, reduceMotion: false) {}
        }
    }
    .frame(width: VaporPanelView.width)
    .padding()
}
#endif
