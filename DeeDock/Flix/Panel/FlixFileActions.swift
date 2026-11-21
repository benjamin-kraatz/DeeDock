import AppKit

/// The file work behind Flix Files' commands: open, reveal, copy, move, rename, trash.
///
/// Every command is a deliberate user action. Moves and renames return what Undo needs; trashing
/// uses `NSWorkspace.recycle`, which records Put Back. Nothing here changes the history; the panel
/// state does that once a command succeeded.
@MainActor
enum FlixFileActions {
    /// Opens items with their default app; links open in the browser they were seen in.
    static func open(_ items: [FlixItem]) {
        for item in items {
            if let link = item.link {
                if let id = link.browserBundleIdentifier,
                   let browser = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    NSWorkspace.shared.open([link.url], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
                } else {
                    NSWorkspace.shared.open(link.url)
                }
            } else if let url = item.url {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Opens files with a specific app, for a drop on an app favorite.
    static func open(_ urls: [URL], withApplicationAt app: URL) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func reveal(_ items: [FlixItem]) {
        HubFileOperations.revealInFinder(items.compactMap(\.url))
    }

    /// Copies the items as Finder does: file URLs, and page URLs for links.
    static func copy(_ items: [FlixItem]) {
        let urls = items.compactMap(\.shareURL)
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    /// Copies POSIX paths, or page addresses for links, one per line.
    static func copyPaths(_ items: [FlixItem]) {
        FilePathCopy.copy(items.compactMap { item in item.url.map(FilePathCopy.path) ?? item.link?.url.absoluteString })
    }

    /// Moves files into `folder`, picking Finder's "copy" name when one is taken. Each file is
    /// moved on its own: one that fails stays where it is and the rest still move.
    /// - Returns: Every move that happened, with the moved file's identity for Undo, and every
    ///   item that could not be moved with the reason. Items already in `folder` appear in neither.
    static func move(_ items: [FlixItem], into folder: URL) -> FlixMoveReport {
        var report = FlixMoveReport()
        for item in items {
            guard let url = item.url, url.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL
            else { continue }
            let name = HubFileNaming.availableName(for: url.lastPathComponent, in: folder) {
                FileManager.default.fileExists(atPath: $0.path)
            }
            let target = folder.appendingPathComponent(name).standardizedFileURL
            do {
                try FileManager.default.moveItem(at: url, to: target)
                report.moved.append(FlixFileMove(item: item, from: url, to: target, identity: FlixFileIdentity.of(target)))
            } catch {
                report.failed.append((item, error.localizedDescription))
            }
        }
        return report
    }

    /// Puts moved or renamed files back, for Undo. A file goes back only when the one at its new
    /// place is still the file that was moved (``FlixFileIdentity``) and its old place is free;
    /// anything else is left alone and reported as skipped.
    static func moveBack(_ moves: [FlixFileMove]) -> FlixUndoReport {
        var report = FlixUndoReport()
        for move in moves {
            if let url = undo(move) { report.restored.append((move.item, url)) } else { report.skipped.append(move) }
        }
        return report
    }

    /// Undoes one move or rename, or returns nil without touching anything.
    static func undo(_ move: FlixFileMove) -> URL? {
        guard let identity = move.identity, identity.matches(move.to) else { return nil }
        // The old place must be free. A rename that changed only letter case finds the same file
        // there on a case-insensitive volume, which is fine.
        let fromIsFree = !FileManager.default.fileExists(atPath: move.from.path) || identity.matches(move.from)
        guard fromIsFree, (try? FileManager.default.moveItem(at: move.to, to: move.from)) != nil else { return nil }
        return move.from
    }

    /// Renames one file in place.
    /// - Returns: The rename, with the renamed file's identity for Undo; nil for an item without a file.
    static func rename(_ item: FlixItem, to name: String) throws -> FlixFileMove? {
        guard let url = item.url else { return nil }
        let renamed = try HubFileOperations.rename(url, to: name)
        return FlixFileMove(item: item, from: url, to: renamed, identity: FlixFileIdentity.of(renamed))
    }

    static func trash(_ items: [FlixItem]) async throws -> [URL] {
        try await HubFileOperations.moveToTrash(items.compactMap(\.url))
    }
}
