import Darwin
import Foundation

/// Removes a staged folder for good, skipping the Trash.
///
/// Runs on its own utility-QoS operation queue, not the Swift concurrency pool: `removefile` blocks
/// for as long as the tree takes, which for `node_modules` can be many seconds. The folder's
/// top-level children are removed at most four at a time, then the (now empty) folder itself.
nonisolated final class VaporRemover: Sendable {
    static let maxConcurrentRemovals = 4

    /// Removes `folder` and everything in it. Returns true only when `lstat` confirms nothing is
    /// left at the path.
    func remove(_ folder: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            let queue = OperationQueue()
            queue.name = "DOKK.Vapor.removal"
            queue.qualityOfService = .utility
            queue.maxConcurrentOperationCount = Self.maxConcurrentRemovals
            // Only a real directory is listed. `contentsOfDirectory` follows a link, so a staged
            // link would expose its target's contents; anything else is removed as itself below.
            let isDirectory = VaporPathCheck(path: folder.path) == .directory
            let children = isDirectory ? (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] : []
            for child in children {
                let path = folder.appendingPathComponent(child).path
                queue.addOperation { Self.removeTree(atPath: path) }
            }
            // A barrier runs after every child has gone, then removes what's left of the folder.
            // The block holds the queue until the last child is gone, so it outlives this scope.
            queue.addBarrierBlock { [queue] in
                withExtendedLifetime(queue) {}
                Self.removeTree(atPath: folder.path)
                // Only a confirmed ENOENT counts as gone; a failed lookup keeps the ledger entry.
                continuation.resume(returning: VaporPathCheck(path: folder.path) == .missing)
            }
        }
    }

    /// `removefile` with `REMOVEFILE_RECURSIVE`. It removes a single file too, and does not follow
    /// symbolic links, so a link inside a cache never deletes its target.
    private static func removeTree(atPath path: String) {
        guard let state = removefile_state_alloc() else { return }
        defer { removefile_state_free(state) }
        _ = removefile(path, state, removefile_flags_t(REMOVEFILE_RECURSIVE))
    }
}
