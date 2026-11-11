import Darwin
import Foundation

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
        guard FileManager.default.fileExists(atPath: request.url.path) else {
            return .failed(folderID: request.folderID, .missing)
        }
        let id = UUID()
        let target = location.stagedURL(for: request.url, id: id)
        // Whole seconds, so the ledger's ISO 8601 dates read back equal.
        let stagedAt = Date(timeIntervalSince1970: now().timeIntervalSince1970.rounded(.down))
        var entry = VaporLedgerEntry(id: id, originalPath: request.url.path, stagedPath: target.path,
                                     bytes: request.bytes, stagedAt: stagedAt, state: .staging)
        var entries = ledger.read()
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
        var entries = ledger.read()
        let outcomes = staged.map { entry -> VaporRestoreOutcome in
            if let code = Self.rename(entry.stagedURL, to: entry.originalURL) {
                return code == EEXIST || code == ENOTEMPTY ? .pathTaken(entry) : .failed(entry, code)
            }
            entries.removeAll { $0.id == entry.id }
            return .restored(entry)
        }
        try? ledger.write(entries)
        return outcomes
    }

    @discardableResult
    func remove(_ staged: [VaporLedgerEntry]) async -> [UUID] {
        var removed: [UUID] = []
        for entry in staged {
            let gone = await remover.remove(entry.stagedURL)
            guard gone else { continue }
            removed.append(entry.id)
            var entries = ledger.read()
            entries.removeAll { $0.id == entry.id }
            try? ledger.write(entries)
        }
        return removed
    }

    @discardableResult
    func recover() async -> Int {
        let entries = ledger.read()
        var toRemove: [VaporLedgerEntry] = []
        var finished: [UUID] = []
        for entry in entries {
            let stagedExists = FileManager.default.fileExists(atPath: entry.stagedPath)
            if stagedExists {
                toRemove.append(entry)
            } else {
                // Either the rename never happened (the folder is still at its original path) or
                // removal already finished. Both mean the entry is done; nothing is restored.
                finished.append(entry.id)
            }
        }
        if !finished.isEmpty {
            try? ledger.write(entries.filter { !finished.contains($0.id) })
        }
        return await remove(toRemove).count
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
