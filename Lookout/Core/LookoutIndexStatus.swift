import Foundation

/// What the index service is doing and what the index holds (`LookoutIndexClient.indexStatusDidChange`).
///
/// `current` names a file the user has; it is for the onboarding feed only and must never reach analytics.
nonisolated struct LookoutIndexStatus: Codable, Sendable, Equatable {
    /// What the service is doing.
    enum Activity: Codable, Sendable, Equatable {
        /// Nothing it may do right now: all indexed, or the backfill isn't allowed. The service exits about a minute
        /// later.
        case idle
        /// Walking the folders and reconciling the index.
        case syncing
        /// The first pass: new files, then the backfill.
        case indexing
        /// The later pass over long PDFs and documents (`Indexer.finishLongFiles`).
        case finishingLongFiles
        /// The model files aren't all there; file names are searchable meanwhile.
        case waitingForModel
        /// `pause()` was called.
        case paused
        /// Indexing had to stop (the index can't be opened, the model can't be loaded).
        case failed(message: String)
    }

    /// The file just read, for the onboarding feed.
    struct CurrentFile: Codable, Sendable, Equatable {
        let kind: FileKind
        /// The file name alone, never the path.
        let name: String
    }

    var activity: Activity = .idle
    /// Progress through the current pass: files for the first pass, pages and chunks for the later pass.
    var done = 0
    var total = 0
    /// Files by kind and state, vectors, unfinished long files: within the folders that are there now.
    var counts = IndexStore.Counts()
    /// Chosen folders that aren't there (an unplugged drive): their files stay in the index.
    var missingRoots: [String] = []
    /// Chosen folders macOS won't let the service read (Files and Folders privacy): skipped, never retried in a loop.
    var notPermittedRoots: [String] = []
    /// Whether the backfill may run (the app's power policy).
    var backfillAllowed = false
    /// When the stored vectors last changed (files embedded, or vectors removed with changed, removed or pruned
    /// files, or a model reset), so the app knows when to reload what it searches. Nil until they first do in this
    /// process.
    var vectorsChangedAt: Date?
    var current: CurrentFile?

    func encoded() throws -> Data { try LookoutJSON.encode(self) }

    static func decode(_ data: Data) throws -> LookoutIndexStatus {
        try LookoutJSON.decode(LookoutIndexStatus.self, from: data)
    }
}
