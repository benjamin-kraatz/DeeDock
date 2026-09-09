import SwiftUI
import UniformTypeIdentifiers

/// Formats already-loaded metadata; rendering never opens a file or measures folder contents.
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
        guard !reference.isFolder, let bytes = reference.byteCount, bytes >= 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var summary: String {
        [kind, size, reference.modifiedAt.map(Self.shortDate.string(from:))]
            .compactMap { $0 }.joined(separator: " · ")
    }

    func gridDetail(sort: FolderStackSort) -> String? {
        switch sort {
        case .recency: reference.modifiedAt.map(Self.shortDate.string(from:))
        case .alphabetical: kind
        case .size: reference.isFolder ? kind : size
        }
    }

    var help: String {
        var lines = [reference.name, reference.url.path, [kind, size].compactMap { $0 }.joined(separator: " · ")]
        if let modified = reference.modifiedAt {
            lines.append(String(localized: .folderDetailsModified) + ": " + Self.exactDate.string(from: modified))
        }
        if let created = reference.createdAt {
            lines.append(String(localized: .folderDetailsCreated) + ": " + Self.exactDate.string(from: created))
        }
        return lines.joined(separator: "\n")
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
