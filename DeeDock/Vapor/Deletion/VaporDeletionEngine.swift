import Darwin
import Foundation
import os

/// One folder the controller asks to stage.
nonisolated struct VaporStageRequest: Equatable, Sendable {
    /// The folder's id in the orb, carried through so results map back to rows.
    let folderID: UUID
    let url: URL
    let bytes: Int64
}

/// The result of staging one folder.
nonisolated enum VaporStageOutcome: Equatable, Sendable {
    case staged(folderID: UUID, entry: VaporLedgerEntry)
    case failed(folderID: UUID, VaporStagingFailure)

    var folderID: UUID {
        switch self {
        case .staged(let id, _), .failed(let id, _): id
        }
    }
}

/// The result of undoing one staged folder.
nonisolated enum VaporRestoreOutcome: Equatable, Sendable {
    case restored(VaporLedgerEntry)
    /// Something now sits at the original path. The folder stays staged and is removed later.
    case pathTaken(VaporLedgerEntry)
    /// The rename back failed for another reason, such as a deleted parent folder.
    case failed(VaporLedgerEntry, Int32)
}

/// Staging, undo, removal and launch recovery, behind a protocol so the controller can be tested
/// with a fake.
nonisolated protocol VaporDeleting: Sendable {
    func stage(_ requests: [VaporStageRequest]) async -> [VaporStageOutcome]
    func restore(_ entries: [VaporLedgerEntry]) async -> [VaporRestoreOutcome]
    /// Removes staged folders for good and clears their ledger entries. Returns the ids removed.
    @discardableResult func remove(_ entries: [VaporLedgerEntry]) async -> [UUID]
    /// Finishes every ledger entry left by an earlier run. Returns how many were removed.
    @discardableResult func recover() async -> Int
}

/// Owns the ledger and every rename Vapor makes. Being an actor serializes ledger writes.
///
/// Ordering is what makes it safe to quit at any point:
/// 1. the ledger entry is written in the `staging` state,
/// 2. the folder is renamed with `RENAME_EXCL`, so nothing is ever overwritten,
/// 3. the entry becomes `staged`.
/// Undo renames back with `RENAME_EXCL` too, and leaves the folder staged if the original path
/// is taken. Recovery never restores: it only finishes removal.
actor VaporDeletionEngine: VaporDeleting {
    private let ledger: VaporLedgerFile
    private let location: VaporStagingLocation
    private let remover = VaporRemover()
    private let now: @Sendable () -> Date
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DOKK", category: "Vapor")

    init(ledger: VaporLedgerFile = .standard, location: VaporStagingLocation = .standard,
         now: @escaping @Sendable () -> Date = Date.init) {
        self.ledger = ledger
        self.location = location
        self.now = now
    }

    func stage(_ requests: [VaporStageRequest]) -> [VaporStageOutcome] {
        requests.map(stage)
    }

    private func stage(_ request: VaporStageRequest) -> VaporStageOutcome {
        // `lstat`, not `fileExists`: a folder swapped for a link since it was added must not be
        // renamed, or removal would later reach whatever the link points to.
        switch VaporPathCheck(path: request.url.path) {
        case .directory: break
        case .missing: return .failed(folderID: request.folderID, .missing)
        case .notDirectory: return .failed(folderID: request.folderID, .changed)
        case .unknown: return .failed(folderID: request.folderID, .other(EIO))
        }
        let id = UUID()
        let target = location.stagedURL(for: request.url, id: id)
        // Whole seconds, so the ledger's ISO 8601 dates read back equal.
        let stagedAt = Date(timeIntervalSince1970: now().timeIntervalSince1970.rounded(.down))
        var entry = VaporLedgerEntry(id: id, originalPath: request.url.path, stagedPath: target.path,
                                     bytes: request.bytes, stagedAt: stagedAt, state: .staging)
        guard var entries = ledger.readExisting() else {
            // The existing ledger can't be read; writing a new one would lose its records.
            return .failed(folderID: request.folderID, .other(EIO))
        }
        entries.append(entry)
        do {
            try ledger.write(entries)
        } catch {
            // Without a ledger entry a crash could strand the folder, so don't rename.
            return .failed(folderID: request.folderID, .other(EIO))
        }
        if let code = Self.rename(request.url, to: target) {
            entries.removeAll { $0.id == id }
            try? ledger.write(entries)
            return .failed(folderID: request.folderID, VaporStagingFailure(errno: code))
        }
        entry.state = .staged
        if let index = entries.firstIndex(where: { $0.id == id }) { entries[index] = entry }
        try? ledger.write(entries)
        return .staged(folderID: request.folderID, entry: entry)
    }

    func restore(_ staged: [VaporLedgerEntry]) -> [VaporRestoreOutcome] {
        // Nil when the ledger can't be read: the renames still happen, but the file is left as
        // it is rather than replaced with a list that lost other folders' records.
        var entries = ledger.readExisting()
        let outcomes = staged.map { entry -> VaporRestoreOutcome in
            if let code = Self.rename(entry.stagedURL, to: entry.originalURL) {
                return code == EEXIST || code == ENOTEMPTY ? .pathTaken(entry) : .failed(entry, code)
            }
            entries?.removeAll { $0.id == entry.id }
            return .restored(entry)
        }
        if let entries { try? ledger.write(entries) }
        return outcomes
    }

    @discardableResult
    func remove(_ staged: [VaporLedgerEntry]) async -> [UUID] {
        var removed: [UUID] = []
        for entry in staged {
            // Defence in depth: recovery validates before it gets here, and Undo-window entries
            // come from this session's own `stage`, but nothing reaches `removefile` unchecked.
            guard mayRemove(entry) else {
                Self.logger.error("Vapor skipped removing a ledger entry that is not a staged folder")
                continue
            }
            let gone = await remover.remove(entry.stagedURL)
            // "Not there" only counts when its folder is: on a disk that was unplugged, the
            // staged folder still exists, and the entry must outlive the disconnection.
            guard gone, Self.isReachable(entry) else { continue }
            removed.append(entry.id)
            guard var entries = ledger.readExisting() else { continue }
            entries.removeAll { $0.id == entry.id }
            try? ledger.write(entries)
        }
        return removed
    }

    @discardableResult
    func recover() async -> Int {
        guard let entries = ledger.readExisting() else { return 0 }
        var toRemove: [VaporLedgerEntry] = []
        var finished: [UUID] = []
        for entry in entries {
            switch VaporPathCheck(path: entry.stagedPath) {
            case .directory where mayRemove(entry):
                toRemove.append(entry)
            case .directory, .notDirectory:
                // The ledger names something Vapor never staged: a path of the wrong shape, a
                // folder someone else owns, or a file or link (`stage` only renames real
                // folders). Recovery deletes recursively without the Trash, so a corrupt or
                // edited ledger must never choose what goes. Drop the entry, leave the disk alone.
                Self.logger.error("Vapor dropped a ledger entry that does not name a staged folder")
                finished.append(entry.id)
            case .missing where Self.isReachable(entry):
                // Either the rename never happened (the folder is still at its original path) or
                // removal already finished. Both mean the entry is done; nothing is restored.
                finished.append(entry.id)
            case .missing, .unknown:
                // An unplugged disk or a failed lookup: keep the entry for a later launch.
                break
            }
        }
        if !finished.isEmpty {
            try? ledger.write(entries.filter { !finished.contains($0.id) })
        }
        return await remove(toRemove).count
    }

    /// Whether `entry` may be handed to the remover: its staged path has a shape ``stage`` produces
    /// for that entry, and `lstat` finds either nothing there (removal then only confirms it's gone)
    /// or a real directory owned by the current user. Never a link, a file, or another user's
    /// folder, since the remover deletes recursively and skips the Trash.
    private func mayRemove(_ entry: VaporLedgerEntry) -> Bool {
        guard location.isStagedPath(entry.stagedURL, id: entry.id, original: entry.originalURL) else { return false }
        var info = stat()
        guard lstat(entry.stagedURL.path, &info) == 0 else { return errno == ENOENT }
        return (info.st_mode & S_IFMT) == S_IFDIR && info.st_uid == getuid()
    }

    /// Whether the folder holding `entry`'s staged path is there, so a missing staged path
    /// means it was removed rather than that its disk is unplugged.
    private static func isReachable(_ entry: VaporLedgerEntry) -> Bool {
        VaporPathCheck(path: entry.stagedURL.deletingLastPathComponent().path) == .directory
    }

    /// The entries currently in the ledger. For tests and diagnostics.
    func ledgerEntries() -> [VaporLedgerEntry] { ledger.read() }

    /// `renamex_np` with `RENAME_EXCL`: fails with `EEXIST` instead of replacing a destination.
    /// Returns nil on success, or the `errno` value.
    private static func rename(_ source: URL, to destination: URL) -> Int32? {
        let result = source.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to -> Int32 in
                guard let from, let to else { return -1 }
                return renamex_np(from, to, UInt32(RENAME_EXCL))
            }
        }
        return result == 0 ? nil : errno
    }
}
