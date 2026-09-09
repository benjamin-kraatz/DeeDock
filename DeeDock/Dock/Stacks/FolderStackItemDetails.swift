import Foundation
import UniformTypeIdentifiers

/// Formats already-loaded metadata, folder contents metrics, and optional media headers.
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

    /// Localized image size, PDF page count, or media duration when that header was loaded.
    var mediaText: String? {
        switch reference.media {
        case .image(let width, let height):
            String(localized: .folderDetailsImageSize(width: width, height: height))
        case .pdf(let pageCount):
            String(localized: .folderDetailsPageCount(count: pageCount))
        case .audio(let duration), .video(let duration):
            Self.durationText(duration)
        case nil:
            nil
        }
    }

    var summary: String {
        [kind, itemCountText, size, mediaText, reference.modifiedAt.map(Self.shortDate.string(from:))]
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
            lines.append([kind, size, mediaText].compactMap { $0 }.joined(separator: " · "))
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

    private static func durationText(_ seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let formatter = seconds >= 3600 ? longDuration : shortDuration
        return formatter.string(from: seconds)
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

    private static let shortDuration: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

    private static let longDuration: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
}
