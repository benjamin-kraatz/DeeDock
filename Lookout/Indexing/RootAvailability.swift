import Darwin
import Foundation

/// Which chosen folders can be crawled right now. Checked before every sync, not once: a drive ejected while the
/// service runs must not crawl as "all deleted", and a folder macOS won't let us read (Files and Folders privacy)
/// looks empty to a crawl, which must never be mistaken for "everything in it was deleted" either. Both keep their
/// rows; the store's `scope` hides them from what's waiting.
///
/// The check lists the folder once with `opendir` and reads nothing else. It never asks for access: a folder that's
/// denied fails with `EPERM` or `EACCES` and is reported as not permitted, and it's looked at again only on the next
/// sync anyone asks for. (macOS may still show its own prompt the first time any process reads a protected folder
/// whose access was never decided; the app chooses folders through an open panel, which settles that.)
///
/// Each root is also checked again on its real path (`Rules.checkRoots`), because a chosen folder can become a link
/// while the service runs: one that now resolves into ~/Library or another folder Lookout never reads is refused and
/// left out of the sync. Its rows stay out of the store's `scope`, and the next configuration prunes them.
nonisolated struct RootAvailability: Sendable, Equatable {
    /// The roots to crawl, at their real paths as of this check.
    var available: [URL] = []
    /// Not there, or not a folder.
    var missing: [String] = []
    /// There, but not readable.
    var notPermitted: [String] = []
    /// Folders Lookout never reads (`Rules.RootRefusal`), as given.
    var refused: [String] = []

    /// - Parameter home: The home folder (`Rules.rootRefusal`).
    static func check(_ roots: [URL], home: String = FileManager.default.homeDirectoryForCurrentUser.path)
        -> RootAvailability {
        var result = RootAvailability()
        for given in roots {
            guard let real = Rules.checkRoots([given.path], home: home).allowed.first else {
                result.refused.append(given.path)
                continue
            }
            let root = URL(fileURLWithPath: real, isDirectory: true)
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isFolder), isFolder.boolValue else {
                result.missing.append(given.path)
                continue
            }
            guard let folder = opendir(root.path) else {
                let error = errno
                if error == EPERM || error == EACCES {
                    result.notPermitted.append(given.path)
                } else {
                    result.missing.append(given.path)
                }
                continue
            }
            closedir(folder)
            result.available.append(root)
        }
        return result
    }
}
