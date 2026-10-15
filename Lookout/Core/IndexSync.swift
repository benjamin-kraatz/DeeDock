// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Foundation

/// Reconciles the index with a crawl: new files are queued, changed ones re-queued, moved ones re-pathed (no
/// re-embedding), and files that are gone or newly excluded are removed.
///
/// DigUp did this inside `Indexer.sync`. It touches only the crawl and the store, never a model, so it lives here,
/// where tests in the app's test target can reach it; `Indexer.sync` crawls and then calls it.
nonisolated enum IndexSync {
    /// What one sync changed.
    struct Summary: Sendable {
        /// `changed` counts every file queued again in place of its segments, including a move that changed the
        /// file's kind (that one counts as `moved` too).
        var added = 0, changed = 0, moved = 0, removed = 0, unchanged = 0
        var crawl: CrawlReport
        /// Files this sync queued for embedding (new or changed), so a watcher can index exactly those first.
        var queued: [Int64] = []

        /// Whether this sync deleted segments the app may have loaded: a changed file (also one moved under a name of
        /// another kind) loses them, and so does a removed one. The app then reloads its vectors.
        var vectorsChanged: Bool { changed + removed > 0 }
    }

    /// Applies `crawl` (a crawl of `roots`) to `store`, in one transaction.
    ///
    /// - Throws: A database error; nothing is changed then.
    @discardableResult
    static func apply(_ crawl: CrawlReport, roots: [URL], to store: IndexStore) throws -> Summary {
        // Real paths, as the walk reports them: rows stored under /private/var must be found from a root given as
        // /var, or every sync would insert them again. A root that isn't there resolves to itself.
        let rootPaths = roots.map { FolderSelection.realPath($0.standardizedFileURL.path) }
        let existing = try store.files(under: rootPaths)
        // Moves are matched strictly on the stored device and inode (plus size and date): an inode number means one
        // file only on its own volume, and a volume mounted inside a root has its own numbers. A drive gets a new
        // device number at every mount, so the stored one is kept current instead: a file found unchanged at its path
        // takes the device its candidate reports (below), which is exact for each file, nested volumes included. A
        // rename in the very sync that follows a remount then doesn't match, and that one file is read again.
        var byPath: [String: FileRecord] = [:]
        var byInode: [String: FileRecord] = [:]
        for file in existing {
            byPath[file.path] = file
            byInode["\(file.device):\(file.inode)"] = file
        }
        let seen = Set(crawl.candidates.map(\.path))
        var movedFrom = Set<String>()
        var summary = Summary(crawl: crawl)
        try store.db.transaction {
            for file in crawl.candidates {
                if let row = byPath[file.path] {
                    // Another inode at the same path is another file, even with the same size and date (contents
                    // replaced and the timestamp kept). The device isn't compared: a drive gets a new device number
                    // at every mount, and its files must not be read again for that.
                    if row.size != file.size || abs(row.mtime - file.mtime) > 0.001 || row.kind != file.kind
                        || row.inode != file.inode {
                        try store.requeue(row.id, as: file)
                        summary.changed += 1
                        summary.queued.append(row.id)
                    } else {
                        // Opened since: a pending file moves up the queue. (Spotlight only answers for files it
                        // has a date for, so a missing date never clears a known one.)
                        if let lastUsed = file.lastUsed, lastUsed != row.lastUsed { try store.setLastUsed(row.id, lastUsed) }
                        // Remounted: the same file under the drive's new device number, kept for move matching.
                        if row.device != file.device { try store.setDevice(row.id, file.device) }
                        summary.unchanged += 1
                    }
                } else if let row = byInode["\(file.device):\(file.inode)"], !seen.contains(row.path),
                          !movedFrom.contains(row.path), row.size == file.size, abs(row.mtime - file.mtime) < 0.001 {
                    try store.move(row.id, to: file.path)
                    if row.kind != file.kind {
                        // The new name changed what it is ("capture.png" → "Screenshot capture.png"), and a screenshot
                        // is read differently (OCR): read again as what it is now.
                        try store.requeue(row.id, as: file)
                        summary.changed += 1   // its segments went (`vectorsChanged`)
                        summary.queued.append(row.id)
                    } else if let lastUsed = file.lastUsed, lastUsed != row.lastUsed {
                        try store.setLastUsed(row.id, lastUsed)
                    }
                    movedFrom.insert(row.path)
                    summary.moved += 1
                } else {
                    summary.queued.append(try store.insert(file))
                    summary.added += 1
                }
            }
            // A root that went away while it was being walked (a drive ejected mid-crawl) looked emptier than it is:
            // keep its rows rather than take that for "deleted".
            let vanished = rootPaths.filter { !FileManager.default.fileExists(atPath: $0) }
                .map { $0.hasSuffix("/") ? $0 : $0 + "/" }
            for row in existing where !seen.contains(row.path) && !movedFrom.contains(row.path)
                && !vanished.contains(where: { row.path.hasPrefix($0) }) {
                try store.delete(row.id)
                summary.removed += 1
            }
        }
        return summary
    }
}
