import Darwin
import Foundation

/// What sits at a path, read with `lstat` so a symbolic link is reported as itself rather than
/// as whatever it points to. Staging and removal ask this right before they act, because a
/// folder in the orb can be swapped for a link between Add and Delete.
nonisolated enum VaporPathCheck: Equatable, Sendable {
    case directory
    /// Confirmed absent: `lstat` failed with `ENOENT`.
    case missing
    /// A symbolic link, file or anything else that is not a real directory.
    case notDirectory
    /// The lookup failed for another reason (no permission to search a parent, an I/O error).
    /// Never read as "gone": a ledger entry must outlive it.
    case unknown

    init(path: String) {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            self = errno == ENOENT ? .missing : .unknown
            return
        }
        self = (info.st_mode & S_IFMT) == S_IFDIR ? .directory : .notDirectory
    }
}
