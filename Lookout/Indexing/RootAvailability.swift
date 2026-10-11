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
nonisolated struct RootAvailability: Sendable, Equatable {
    var available: [URL] = []
    /// Not there, or not a folder.
    var missing: [String] = []
    /// There, but not readable.
    var notPermitted: [String] = []

    static func check(_ roots: [URL]) -> RootAvailability {
        var result = RootAvailability()
        for root in roots {
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isFolder), isFolder.boolValue else {
                result.missing.append(root.path)
                continue
            }
            guard let folder = opendir(root.path) else {
                let error = errno
                if error == EPERM || error == EACCES {
                    result.notPermitted.append(root.path)
                } else {
                    result.missing.append(root.path)
                }
                continue
            }
            closedir(folder)
            result.available.append(root)
        }
        return result
    }
}
