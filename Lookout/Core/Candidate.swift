// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

/// A file the crawler decided to index, with the metadata the index compares on the next sync.
nonisolated struct Candidate: Sendable, Equatable {
    let path: String
    let kind: FileKind
    let size: Int64
    /// Seconds since 1970.
    let mtime: Double
    let inode: UInt64
    let device: UInt64
    /// When the file was last opened (Spotlight's `kMDItemLastUsedDate`, seconds since 1970), or nil when Spotlight
    /// doesn't know. The first pass indexes the most recently used files first (`IndexStore.pendingOrderSQL`).
    var lastUsed: Double?
}

/// What a crawl found, and what it left out and why.
nonisolated struct CrawlReport: Sendable {
    var candidates: [Candidate] = []
    /// Reason → files.
    var skipped: [String: Int] = [:]
    /// Reason → folders not walked into.
    var skippedFolders: [String: Int] = [:]
    /// Folder → files skipped as a dataset.
    var datasets: [String: Int] = [:]
}
