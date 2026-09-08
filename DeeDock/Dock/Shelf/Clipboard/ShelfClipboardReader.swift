import AppKit

/// A bounded, immutable snapshot. No pasteboard objects cross the image worker's actor boundary.
nonisolated struct ShelfClipboardSnapshot: Sendable {
    enum Entry: Sendable, Equatable {
        case file(URL)
        case image(Data)
        case invalid
    }

    var entries: [Entry]
    var omitted: Int = 0
    static let maximumItems = 100
    static let maximumBytes = 64 * 1_024 * 1_024
}

/// Parses literal local paths only. Whitespace inside filenames and shell metacharacters are literal.
nonisolated enum ShelfClipboardPaths {
    static let maximumTextBytes = 1_024 * 1_024

    static func url(_ text: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        guard !text.contains("\0"), !text.isEmpty else { return nil }
        if text.hasPrefix("file://") {
            guard let url = URL(string: text), url.isFileURL,
                  url.host == nil || url.host == "" || url.host == "localhost",
                  url.query == nil, url.fragment == nil, !url.path.isEmpty else { return nil }
            return URL(fileURLWithPath: url.path).standardizedFileURL
        }
        if text.hasPrefix("/") { return URL(fileURLWithPath: text).standardizedFileURL }
        if text.hasPrefix("~/") {
            return home.appendingPathComponent(String(text.dropFirst(2))).standardizedFileURL
        }
        return nil
    }

    static func lines(_ text: String) -> [Substring] {
        text.split(whereSeparator: \.isNewline)
    }
}

/// Reads only in response to opening the Shelf menu or invoking Paste. Never observes the clipboard.
@MainActor
enum ShelfClipboardReader {
    static let supportedTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff]

    /// Images and file URLs need no payload read here. Text-path classification can cause the
    /// system's clipboard permission prompt; AppKit has no metadata-only local-path detector.
    static func canPaste(from pasteboard: NSPasteboard = .general) -> Bool {
        if pasteboard.availableType(from: supportedTypes) != nil { return true }
        guard pasteboard.availableType(from: [.string]) != nil,
              pasteboard.accessBehavior != .alwaysDeny,
              let text = pasteboard.string(forType: .string),
              text.utf8.count <= ShelfClipboardPaths.maximumTextBytes else { return false }
        return ShelfClipboardPaths.lines(text).prefix(ShelfClipboardSnapshot.maximumItems)
            .contains { ShelfClipboardPaths.url(String($0)) != nil }
    }

    /// Called synchronously from the paste selector to retain the native user-initiated paste context.
    /// Checks changeCount before and after reading so a changing clipboard cannot produce a mixed batch.
    static func snapshot(from pasteboard: NSPasteboard = .general) throws -> ShelfClipboardSnapshot {
        let change = pasteboard.changeCount
        let items = pasteboard.pasteboardItems ?? []
        var result = ShelfClipboardSnapshot(entries: [])
        var bytes = 0
        for item in items.prefix(ShelfClipboardSnapshot.maximumItems) {
            if result.entries.count >= ShelfClipboardSnapshot.maximumItems {
                result.omitted += 1
                continue
            }
            // A file's thumbnail and display-name representations are never separate imports.
            if item.types.contains(.fileURL) {
                if let text = item.string(forType: .fileURL),
                   text.utf8.count <= ShelfClipboardPaths.maximumTextBytes,
                   let url = ShelfClipboardPaths.url(text) {
                    result.entries.append(.file(url))
                } else { result.entries.append(.invalid) }
            } else if let type = item.availableType(from: [.png, .tiff]) {
                if let data = item.data(forType: type), !data.isEmpty,
                   data.count <= ShelfClipboardSnapshot.maximumBytes - bytes {
                    bytes += data.count
                    result.entries.append(.image(data))
                } else { result.entries.append(.invalid) }
            } else if let text = item.string(forType: .string) {
                guard text.utf8.count <= ShelfClipboardPaths.maximumTextBytes else {
                    result.entries.append(.invalid)
                    continue
                }
                for line in ShelfClipboardPaths.lines(text) {
                    guard result.entries.count < ShelfClipboardSnapshot.maximumItems else {
                        result.omitted += 1
                        continue
                    }
                    result.entries.append(ShelfClipboardPaths.url(String(line)).map { .file($0) } ?? .invalid)
                }
            } else { result.entries.append(.invalid) }
        }
        result.omitted += max(0, items.count - ShelfClipboardSnapshot.maximumItems)
        guard pasteboard.changeCount == change else { throw ShelfClipboardFailure.changed }
        guard !result.entries.isEmpty else { throw ShelfClipboardFailure.unavailable }
        return result
    }
}

nonisolated enum ShelfClipboardFailure: Error, Equatable {
    case changed, unavailable, image, rejected
    case retainedFile(URL)
}
