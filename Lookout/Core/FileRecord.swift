// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

/// A file as the index knows it (a `files` row).
nonisolated struct FileRecord: Sendable {
    let id: Int64
    let path: String
    let kind: FileKind
    let size: Int64
    let mtime: Double
    let inode: UInt64
    let device: UInt64
    /// `pending`, `done`, `partial` (a long file with pages or chunks left), `skipped` or `failed`.
    let state: String
    /// Spotlight's last-used date (seconds since 1970), when it knew one at the last sync that queued the file.
    let lastUsed: Double?
}
