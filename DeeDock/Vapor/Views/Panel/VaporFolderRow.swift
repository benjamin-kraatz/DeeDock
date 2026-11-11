import SwiftUI

/// The scrolling list of folder rows. Caps its height so a long list scrolls inside the panel.
struct VaporFolderList: View {
    let folders: [VaporFolder]
    let home: URL
    let remove: (VaporFolder.ID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(folders) { folder in
                    VaporFolderRow(folder: folder, home: home) { remove(folder.id) }
                }
            }
            .padding(.horizontal, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One folder: icon, name, tag chip, parent path, size and file count, and × on hover.
struct VaporFolderRow: View {
    let folder: VaporFolder
    let home: URL
    let remove: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            VaporFolderIcon(size: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: folder.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    VaporTagChip(classification: folder.classification)
                }
                Text(verbatim: folder.parentPath(home: home))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                if let failure = folder.failure {
                    Text(VaporCopy.failure(failure))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 6)
            VaporRowSize(measurement: folder.measurement)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(Text(.vaporRemove))
            .opacity(hovered ? 1 : 0)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(hovered ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 10, style: .continuous))
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.vaporRowAccessibility(folder.name, String(localized: VaporCopy.tag(folder.classification)),
                                                        folder.parentPath(home: home))))
        .accessibilityValue(Text(verbatim: VaporRowSize.accessibilityValue(folder.measurement)))
        .accessibilityAction(named: Text(.vaporRemove), remove)
    }
}

/// The tag chip; orange for a folder that isn't a known cache.
private struct VaporTagChip: View {
    let classification: VaporClassification

    var body: some View {
        let tint: Color = classification.isKnown ? .secondary : .orange
        Text(VaporCopy.tag(classification))
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tint.opacity(0.14), in: .capsule)
    }
}

/// Size and file count, "Calculating…" while measuring, or "—" when unreadable.
private struct VaporRowSize: View {
    let measurement: VaporMeasurement

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            switch measurement {
            case .pending:
                Text(.vaporRowCalculating)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .unreadable:
                Text(verbatim: "—")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .measured(let bytes, let files):
                Text(verbatim: VaporCopy.size(bytes))
                    .font(.callout.monospacedDigit())
                Text(.vaporFileCount(files))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func accessibilityValue(_ measurement: VaporMeasurement) -> String {
        switch measurement {
        case .pending: String(localized: .vaporRowCalculating)
        case .unreadable: String(localized: .vaporSizeUnavailable)
        case .measured(let bytes, let files):
            String(localized: .vaporAccessibilityJoined(VaporCopy.size(bytes), String(localized: .vaporFileCount(files))))
        }
    }
}

#if DEBUG
#Preview("Rows") {
    VStack(spacing: 0) {
        ForEach(VaporPreviewData.mixed + VaporPreviewData.calculating + VaporPreviewData.failed) { folder in
            VaporFolderRow(folder: folder, home: VaporPreviewData.home) {}
        }
    }
    .frame(width: 340)
    .padding()
}
#endif
