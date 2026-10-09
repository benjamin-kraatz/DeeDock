import AppKit

/// File operations behind Files context menus and keyboard shortcuts.
enum HubFileOperations {
    /// Errors with localized descriptions for alerts.
    nonisolated enum OperationError: LocalizedError, Equatable {
        case emptyName
        case invalidCharacter
        case nameTaken(String)

        var errorDescription: String? {
            switch self {
            case .emptyName: String(localized: .hubFilesErrorEmptyName)
            case .invalidCharacter: String(localized: .hubFilesErrorInvalidCharacter)
            case .nameTaken(let name): String(localized: .hubFilesErrorNameTaken(name))
            }
        }
    }

    /// Moves `urls` to the Trash with `NSWorkspace.recycle`, which also records Put Back.
    /// - Returns: The items' new URLs in the Trash, in the order given (only those macOS reported).
    static func moveToTrash(_ urls: [URL]) async throws -> [URL] {
        let moved = try await NSWorkspace.shared.recycle(urls)
        return urls.compactMap { moved[$0] }
    }

    /// Renames `url` in place.
    ///
    /// Rejects empty names, "/" and ":" (":" is "/" in the POSIX layer, and Finder shows one as the
    /// other), and names already used in the folder. A case-only change ("report" → "Report") is
    /// allowed on case-insensitive volumes.
    /// - Returns: The renamed item's URL.
    /// - Throws: `OperationError` or the file system's error.
    static func rename(_ url: URL, to newName: String) throws -> URL {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != ".." else { throw OperationError.emptyName }
        guard !name.contains("/"), !name.contains(":") else { throw OperationError.invalidCharacter }
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        if name == url.lastPathComponent { return url }
        let caseOnly = name.lowercased() == url.lastPathComponent.lowercased()
        if !caseOnly, FileManager.default.fileExists(atPath: target.path) { throw OperationError.nameTaken(name) }
        try FileManager.default.moveItem(at: url, to: target)
        return target.standardizedFileURL
    }

    /// Creates "untitled folder" (localized), or "untitled folder 2" and up when taken.
    /// - Returns: The new folder's URL.
    static func makeFolder(in folder: URL, baseName: String) throws -> URL {
        var name = baseName
        var index = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "\(baseName) \(index)"
            index += 1
        }
        let url = folder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url.standardizedFileURL
    }

    /// Opens Finder windows with the items selected.
    static func revealInFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Opens each item with its default app (folders open in Finder).
    static func open(_ urls: [URL]) {
        for url in urls { NSWorkspace.shared.open(url) }
    }
}
