import AppKit
import SwiftUI

/// Shared item artwork and text for List, Smart, and Grid presentations.
struct FolderStackItemLabel: View {
    let entry: FolderStackEntry
    let grid: Bool
    let sort: FolderStackSort
    private var details: FolderStackItemDetails { FolderStackItemDetails(reference: entry.reference) }

    var body: some View {
        Group {
            if grid {
                VStack(spacing: 6) {
                    Image(nsImage: entry.icon).resizable().scaledToFit().frame(width: 48, height: 48)
                    Text(verbatim: entry.reference.name).font(.caption).lineLimit(2)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    if let detail = details.gridDetail(sort: sort) {
                        Text(verbatim: detail).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).frame(maxWidth: .infinity)
                    }
                }
                .frame(minHeight: 96)
            } else {
                HStack(spacing: 10) {
                    Image(nsImage: entry.icon).resizable().scaledToFit().frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: entry.reference.name).lineLimit(1)
                        Text(verbatim: details.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .frame(minHeight: 50)
            }
        }
    }
}

#if DEBUG
@MainActor private enum FolderStackItemLabelPreviewData {
    static let icon = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!
    static func entry(name: String, media: FolderStackMediaMetadata?) -> FolderStackEntry {
        FolderStackEntry(
            reference: FolderStackEntryReference(
                url: URL(fileURLWithPath: "/Preview/\(name)"),
                name: name,
                isFolder: false,
                contentType: "public.png",
                byteCount: 1_024,
                modifiedAt: Date(timeIntervalSince1970: 1_780_100_000),
                media: media
            ),
            icon: icon
        )
    }
}

#Preview("List image size") {
    FolderStackItemLabel(entry: FolderStackItemLabelPreviewData.entry(name: "Harbor.png", media: .image(width: 1920, height: 1080)),
                         grid: false, sort: .recency)
        .frame(width: 360).padding()
}

#Preview("List PDF pages") {
    FolderStackItemLabel(entry: FolderStackItemLabelPreviewData.entry(name: "Brief.pdf", media: .pdf(pageCount: 1)),
                         grid: false, sort: .recency)
        .frame(width: 360).padding()
}

#Preview("Grid stays concise") {
    FolderStackItemLabel(entry: FolderStackItemLabelPreviewData.entry(name: "Harbor.png", media: .image(width: 1920, height: 1080)),
                         grid: true, sort: .alphabetical)
        .frame(width: 120).padding()
}

#Preview("List unavailable media") {
    FolderStackItemLabel(entry: FolderStackItemLabelPreviewData.entry(name: "notes.txt", media: nil),
                         grid: false, sort: .recency)
        .frame(width: 360).padding()
}
#endif
