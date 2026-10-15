import Foundation

/// Deletes what Lookout keeps on disk for "Delete index and model": the index database and the files SQLite keeps
/// beside it (`LookoutPaths.indexFiles`), the model files (`LookoutPaths.models`) and unfinished downloads
/// (`LookoutPaths.partialDownloads`). Nothing else in the base folder (the services' logs) and nothing outside it is
/// touched, and the person's own files never are.
///
/// Callers close the index first (`LookoutEngine.deleteIndexAndModel`), so no process writes to a deleted file.
nonisolated enum LookoutDataRemoval {
    /// What gets deleted, in order.
    static func targets(in paths: LookoutPaths) -> [URL] {
        paths.indexFiles + [paths.models, paths.partialDownloads]
    }

    /// Deletes every target that exists. Each target is tried even after one fails.
    ///
    /// - Throws: The first failure, after trying the rest.
    static func removeNow(in paths: LookoutPaths, fileManager: FileManager = .default) throws {
        var firstError: Error?
        for target in targets(in: paths) where fileManager.fileExists(atPath: target.path) {
            do {
                try fileManager.removeItem(at: target)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }

    /// `removeNow` off the main actor: removing an 865 MB model folder can take a moment on a slow disk.
    @concurrent static func remove(in paths: LookoutPaths) async throws {
        try removeNow(in: paths)
    }
}
