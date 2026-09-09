import SwiftUI
import UniformTypeIdentifiers

/// Formats already-loaded metadata and folder contents metrics.
///
/// Rendering never opens a file or starts a folder walk. Folder size uses measured
/// contents totals only, never the directory entry's own `fileSize`.
struct FolderStackItemDetails {
    let reference: FolderStackEntryReference

    var kind: String {
        if reference.isFolder { return String(localized: .folderDetailsFolder) }
        if let identifier = reference.contentType, let description = UTType(identifier)?.localizedDescription {
            return description
        }
        if let description = UTType(filenameExtension: reference.url.pathExtension)?.localizedDescription {
            return description
        }
        return String(localized: .folderDetailsFile)
    }

    var size: String? {
        if reference.isFolder { return folderSizeText }
        guard let bytes = reference.byteCount, bytes >= 0 else { return nil }
        return Self.bytes(bytes)
    }

    var itemCountText: String? {
        guard reference.isFolder, let count = reference.contents?.immediateItemCount else { return nil }
        return String(localized: .folderDetailsItemCount(count))
    }

    var summary: String {
        [kind, itemCountText, size, reference.modifiedAt.map(Self.shortDate.string(from:))]
            .compactMap { $0 }.joined(separator: " · ")
    }

    func gridDetail(sort: FolderStackSort) -> String? {
        switch sort {
        case .recency: reference.modifiedAt.map(Self.shortDate.string(from:))
        case .alphabetical: reference.isFolder ? (itemCountText ?? kind) : kind
        case .size: size ?? (reference.isFolder ? kind : nil)
        }
    }

    var help: String {
        var lines = [reference.name, reference.url.path]
        if reference.isFolder {
            lines.append(kind)
            if let itemCountText { lines.append(itemCountText) }
            if let size {
                lines.append(String(localized: .folderDetailsTotalSize) + ": " + size)
            }
            if let contents = reference.contents,
               let nested = contents.recursiveItemCount,
               let immediate = contents.immediateItemCount,
               nested != immediate {
                lines.append(String(localized: .folderDetailsNestedItemCount(nested)))
            }
        } else {
            lines.append([kind, size].compactMap { $0 }.joined(separator: " · "))
        }
        if let modified = reference.modifiedAt {
            lines.append(String(localized: .folderDetailsModified) + ": " + Self.exactDate.string(from: modified))
        }
        if let created = reference.createdAt {
            lines.append(String(localized: .folderDetailsCreated) + ": " + Self.exactDate.string(from: created))
        }
        return lines.joined(separator: "\n")
    }

    private var folderSizeText: String? {
        guard let contents = reference.contents else { return nil }
        switch contents.completeness {
        case .calculating:
            return String(localized: .folderDetailsCalculating)
        case .complete:
            guard let bytes = contents.totalByteCount else { return nil }
            return Self.bytes(bytes)
        case .incomplete:
            guard let bytes = contents.totalByteCount else { return String(localized: .folderDetailsCalculating) }
            return String(localized: .folderDetailsIncompleteSize(Self.bytes(bytes)))
        }
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private static let exactDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        return formatter
    }()
}

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
