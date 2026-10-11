// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Darwin
import Foundation

/// Where the indexer writes the images it hands the model (resized photos, rendered pages): one folder per process,
/// `$TMPDIR/Lookout-<pid>`, so a process that was killed mid-batch leaves a folder the next one can recognize and
/// remove.
nonisolated enum ScratchFolder {
    static let prefix = "Lookout-"

    /// This process's folder (not created here).
    static var current: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)\(getpid())")
    }

    /// Removes the folders of indexing processes that are gone.
    static func removeStale() {
        let temp = FileManager.default.temporaryDirectory
        for name in (try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? [] {
            guard name.hasPrefix(prefix), let pid = Int32(name.dropFirst(prefix.count)),
                  pid != getpid(), kill(pid, 0) != 0, errno == ESRCH else { continue }
            try? FileManager.default.removeItem(at: temp.appendingPathComponent(name))
        }
    }
}
