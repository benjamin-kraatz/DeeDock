// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

/// Why indexing stops as a whole (as opposed to one file failing).
nonisolated enum IndexerError: Error, CustomStringConvertible {
    /// The index was built with another model or other settings, and the indexer wasn't told to start over
    /// (`Indexer.resetOnModelChange`).
    case fingerprintMismatch(index: String, now: String)

    var description: String {
        switch self {
        case .fingerprintMismatch(let index, let now):
            "this index was built with different settings or model:\n  index: \(index)\n  now:   \(now)\n"
                + "vectors from different settings can't be compared; reset the index"
        }
    }
}
