import Foundation

/// The file system work behind Flix Files' destructive commands: move, rename, Undo, and the
/// identity check that runs before each of them.
///
/// Synchronous and nonisolated: callers run these on ``FlixFileWorker`` so the main actor never
/// waits for the disk. Nothing here changes the history; the panel state applies the results.
///
/// Every command re-reads the file at the item's path first (``check(_:)``) and acts only when it is
/// still the file the row lists (``FlixItem/fileIdentity``). A row without an identity yet counts as
/// changed: Flix Files refuses rather than guess, the caller stores what is there now, and the next
/// attempt acts on it. The check and the operation are separate system calls, so a file replaced in
/// the instant between them is not caught; the check closes the realistic gap (a row listed days
/// ago whose file was replaced since).
nonisolated enum FlixFileOperations {
    /// What is at an item's path compared with the identity its row recorded.
    enum Check: Equatable, Sendable {
        /// Still the listed file.
        case same
        /// Something else is there, or nothing (`current` nil).
        case changed(current: FlixFileIdentity?)
        /// The row has no identity yet; `current` is what is there now.
        case unchecked(current: FlixFileIdentity?)
    }

    /// Compares the file at `item`'s path with the identity its row recorded.
    static func check(_ item: FlixItem) -> Check {
        guard let url = item.url else { return .changed(current: nil) }
        let current = FlixFileIdentity.of(url)
        guard let recorded = item.fileIdentity else { return .unchecked(current: current) }
        return current == recorded ? .same : .changed(current: current)
    }

    /// ``check(_:)`` as a stale record, or nil when the file is still the listed one.
    static func staleness(of item: FlixItem) -> FlixStaleFile? {
        switch check(item) {
        case .same: nil
        case .changed(let current): FlixStaleFile(item: item, current: current, wasUnchecked: false)
        case .unchecked(let current): FlixStaleFile(item: item, current: current, wasUnchecked: true)
        }
    }

    /// Moves files into `folder`, picking Finder's "copy" name when one is taken. Each file is
    /// checked and moved on its own: one that changed or fails stays where it is and the rest still
    /// move.
    /// - Returns: Every move that happened, with the moved file's identity for Undo; every item that
    ///   could not be moved with the reason; every item left alone because it changed. Items already
    ///   in `folder` appear in none of them.
    static func move(_ items: [FlixItem], into folder: URL) -> FlixMoveReport {
        var report = FlixMoveReport()
        for item in items {
            guard let url = item.url, url.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL
            else { continue }
            if let stale = staleness(of: item) {
                report.stale.append(stale)
                continue
            }
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

    /// What renaming one file did.
    enum RenameOutcome: Sendable {
        case renamed(FlixFileMove)
        /// The file changed since the row listed it; nothing was renamed.
        case stale(FlixStaleFile)
        case failed(String)
    }

    /// Renames one file in place, after checking it is still the listed one.
    static func rename(_ item: FlixItem, to name: String) -> RenameOutcome {
        guard let url = item.url else { return .failed(CocoaError(.fileNoSuchFile).localizedDescription) }
        if let stale = staleness(of: item) { return .stale(stale) }
        do {
            let renamed = try HubFileOperations.rename(url, to: name)
            return .renamed(FlixFileMove(item: item, from: url, to: renamed, identity: FlixFileIdentity.of(renamed)))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// One Tidy suggestion's outcome: the combined move from where the file was to where it ended,
    /// for one Undo, and which parts were applied.
    struct TidyOutcome: Sendable {
        var itemID: FlixItem.ID
        var undo: FlixFileMove?
        var renamed: FlixFileMove?
        var moved: FlixFileMove?
        var stale: FlixStaleFile?
    }

    /// Applies a rename and then a move to one file, checking its identity once before either.
    static func tidy(_ item: FlixItem, rename name: String?, moveTo folder: String?) -> TidyOutcome {
        var outcome = TidyOutcome(itemID: item.id)
        guard let original = item.url else { return outcome }
        if let stale = staleness(of: item) {
            outcome.stale = stale
            return outcome
        }
        var current = item
        var last: FlixFileMove?
        if let name, let renamed = try? HubFileOperations.rename(original, to: name) {
            let move = FlixFileMove(item: item, from: original, to: renamed, identity: FlixFileIdentity.of(renamed))
            current.path = renamed.path
            current.fileIdentity = move.identity
            outcome.renamed = move
            last = move
        }
        if let folder {
            // The rename just happened here, so the identity it read is current.
            let report = move([current], into: URL(fileURLWithPath: folder))
            if let move = report.moved.first {
                outcome.moved = move
                last = move
            }
        }
        if let last, last.to != original {
            outcome.undo = FlixFileMove(item: item, from: original, to: last.to, identity: last.identity)
        }
        return outcome
    }

    /// Puts moved or renamed files back, for Undo. A file goes back only when the one at its new
    /// place is still the file that was moved (``FlixFileIdentity``) and its old place is free;
    /// anything else is left alone and reported as skipped.
    static func moveBack(_ moves: [FlixFileMove]) -> FlixUndoReport {
        var report = FlixUndoReport()
        for move in moves {
            if let url = undo(move) { report.restored.append((move.item, url, move.identity)) } else { report.skipped.append(move) }
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

    /// Splits items for the Trash into those still the listed file and those that changed.
    static func trashable(_ items: [FlixItem]) -> (ready: [FlixItem], stale: [FlixStaleFile]) {
        var ready: [FlixItem] = []
        var stale: [FlixStaleFile] = []
        for item in items where item.url != nil {
            if let changed = staleness(of: item) { stale.append(changed) } else { ready.append(item) }
        }
        return (ready, stale)
    }

    /// The identities of files at `paths`, for rows that have none yet. Only paths `policy` lets
    /// Flix Files read are examined, so this can never make macOS ask for folder access.
    static func identities(of paths: [String], policy: FlixReadPolicy) -> [String: FlixFileIdentity] {
        var found: [String: FlixFileIdentity] = [:]
        for path in paths where policy.canRead(path) {
            if let identity = FlixFileIdentity.of(URL(fileURLWithPath: path)) { found[path] = identity }
        }
        return found
    }
}
