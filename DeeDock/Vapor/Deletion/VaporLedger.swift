import Foundation

/// One folder Vapor has staged, or is about to stage, for deletion.
nonisolated struct VaporLedgerEntry: Codable, Equatable, Identifiable, Sendable {
    enum State: String, Codable, Sendable {
        /// Written before the rename. If DOKK stops here, recovery checks which path exists.
        case staging
        /// The rename succeeded; the folder sits at `stagedPath` until removal or Undo.
        case staged
    }

    let id: UUID
    let originalPath: String
    let stagedPath: String
    /// The measured size when the delete started, for "Freed …". Zero when it was still pending.
    let bytes: Int64
    let stagedAt: Date
    var state: State

    var originalURL: URL { URL(fileURLWithPath: originalPath) }
    var stagedURL: URL { URL(fileURLWithPath: stagedPath) }
}

/// The JSON file that records staged folders, so a crash or quit during the undo window never
/// leaves a renamed folder behind: the next launch finishes removing it.
///
/// Not thread-safe by itself. ``VaporDeletionEngine`` is its only owner and serializes access.
nonisolated struct VaporLedgerFile: Sendable {
    let url: URL

    /// The production ledger, `~/Library/Application Support/DOKK/Vapor/ledger.json`.
    static var standard: VaporLedgerFile {
        VaporLedgerFile(url: URL.applicationSupportDirectory.appending(path: "DOKK/Vapor/ledger.json"))
    }

    /// Every entry, or an empty list when the file is missing or unreadable.
    func read() -> [VaporLedgerEntry] {
        readExisting() ?? []
    }

    /// Every entry, an empty list when there is no file, or nil when a file exists but can't be
    /// read or decoded. Staging uses this: writing over an unreadable ledger would drop the
    /// records of folders already staged and strand them.
    func readExisting() -> [VaporLedgerEntry]? {
        // Only a confirmed ENOENT means "no ledger yet"; `fileExists` is also false for a path
        // it can't reach, and treating that as empty would let the next write replace it.
        switch VaporPathCheck(path: url.path) {
        case .missing: return []
        case .unknown: return nil
        case .directory, .notDirectory: break
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([VaporLedgerEntry].self, from: data)
    }

    /// Replaces the file atomically. An empty list removes the file.
    func write(_ entries: [VaporLedgerEntry]) throws {
        if entries.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: url, options: .atomic)
    }
}
