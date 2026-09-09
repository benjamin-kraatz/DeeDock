import Foundation
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
        [kind, size, mediaText, reference.modifiedAt.map(Self.shortDate.string(from:))]
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
        var lines = [reference.name, reference.url.path, [kind, size, mediaText].compactMap { $0 }.joined(separator: " · ")]
        if let modified = reference.modifiedAt {
            lines.append(String(localized: .folderDetailsModified) + ": " + Self.exactDate.string(from: modified))
        }
        if let created = reference.createdAt {
            lines.append(String(localized: .folderDetailsCreated) + ": " + Self.exactDate.string(from: created))
        }
        return lines.joined(separator: "\n")
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
