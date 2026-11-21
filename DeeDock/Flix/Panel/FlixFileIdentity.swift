import Foundation

/// Which file sits at a path, so Undo moves back the file Flix Files moved and never one that took
/// its place.
///
/// Read with `lstat` (a link is described, not followed): the volume and inode, which a move within
/// a volume keeps and nothing else shares, and for files also the size and modification time, so a
/// file that was replaced in place, or rewritten after the move, no longer matches. A folder is
/// matched by volume and inode only, because adding a file to it changes its own dates.
nonisolated struct FlixFileIdentity: Equatable, Sendable {
    var device: Int64
    var inode: UInt64
    var isDirectory: Bool
    /// Nil for folders.
    var size: Int64?
    /// Nanoseconds since 1970; nil for folders.
    var modified: Int64?

    /// The identity of what is at `url` now, or nil when nothing is.
    static func of(_ url: URL) -> FlixFileIdentity? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        let isDirectory = info.st_mode & S_IFMT == S_IFDIR
        let modified = Int64(info.st_mtimespec.tv_sec) &* 1_000_000_000 &+ Int64(info.st_mtimespec.tv_nsec)
        return FlixFileIdentity(device: Int64(info.st_dev), inode: UInt64(info.st_ino), isDirectory: isDirectory,
                                size: isDirectory ? nil : Int64(info.st_size), modified: isDirectory ? nil : modified)
    }

    /// Whether the item at `url` is still this one.
    func matches(_ url: URL) -> Bool { Self.of(url) == self }
}

/// One file Flix Files moved or renamed, with what Undo needs to put exactly that file back.
nonisolated struct FlixFileMove: Sendable {
    var item: FlixItem
    var from: URL
    var to: URL
    /// The moved file as it was right after the move, at `to`. Nil when it could not be read, in
    /// which case Undo refuses rather than guess.
    var identity: FlixFileIdentity?
}

/// The outcome of moving several files: each one moved, or why not.
nonisolated struct FlixMoveReport: Sendable {
    var moved: [FlixFileMove] = []
    /// Items that stayed where they were, with the reason.
    var failed: [(item: FlixItem, message: String)] = []
}

/// The outcome of an Undo: what went back, and what was left alone because it changed or moved.
nonisolated struct FlixUndoReport: Sendable {
    var restored: [(item: FlixItem, url: URL)] = []
    var skipped: [FlixFileMove] = []
}
