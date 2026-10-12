import Foundation

/// Checks a downloaded model file and moves it to its final name in `LookoutPaths.models`. Only a file whose size and
/// SHA-256 match the pinned ones gets there, so the services (and `ModelFiles.missing`) treat any file with a final
/// name as good.
nonisolated enum LookoutModelInstaller {
    /// Verifies `partial` against `file` and moves it into `models`, replacing anything at the final name.
    ///
    /// Hashing reads the file in 8 MB pieces (`ModelFiles.sha256`, about half a second for the 555 MB file) on
    /// `queue`, never on Swift's cooperative thread pool (`LookoutBlockingWork`). A mismatch deletes the partial file,
    /// so the next attempt starts from scratch. Cancelling the caller stops the hashing between pieces and keeps the
    /// partial file, so the next run verifies it again; a file that was verified is moved into place.
    ///
    /// - Throws: `LookoutDownloadError.incomplete` or `.checksumMismatch`, `.write` when the file can't be read
    ///   or moved, or `CancellationError`.
    static func install(_ file: ModelFiles.File, from partial: URL, into models: URL) async throws {
        try await LookoutBlockingWork.run(on: queue) { cancellation in
            try installNow(file, from: partial, into: models, checkCancellation: cancellation.check)
        }
    }

    /// Where downloaded files are hashed and moved, at the priority the download runs at.
    private static let queue = DispatchQueue(label: "Lookout.ModelInstall", qos: .userInitiated)

    /// `install` on the calling thread.
    ///
    /// - Parameter checkCancellation: Asked between the hash's pieces; a `CancellationError` it throws passes through
    ///   and leaves the partial file as it is.
    static func installNow(_ file: ModelFiles.File, from partial: URL, into models: URL,
                           checkCancellation: () throws -> Void = {}) throws {
        let fileManager = FileManager.default
        let size = (try? fileManager.attributesOfItem(atPath: partial.path)[.size] as? Int64) ?? -1
        guard size == file.bytes else {
            try? fileManager.removeItem(at: partial)
            throw LookoutDownloadError.incomplete
        }
        let digest: String
        do {
            digest = try ModelFiles.sha256(of: partial, checkCancellation: checkCancellation)
        } catch let cancelled as CancellationError {
            throw cancelled
        } catch {
            throw LookoutDownloadError.write(reason: error.localizedDescription)
        }
        guard digest == file.sha256 else {
            try? fileManager.removeItem(at: partial)
            throw LookoutDownloadError.checksumMismatch
        }
        do {
            try fileManager.createDirectory(at: models, withIntermediateDirectories: true)
            let destination = models.appending(path: file.name, directoryHint: .notDirectory)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.moveItem(at: partial, to: destination)
        } catch {
            throw LookoutDownloadError.write(reason: error.localizedDescription)
        }
    }
}

/// The free-space check before a download.
nonisolated enum LookoutDiskSpace {
    /// Room kept free beyond the files themselves. A fresh download of both files then needs about 1 GB.
    static let headroom: Int64 = 128 << 20

    /// The bytes still to fetch for `files` given what's already in their partial files, plus `headroom`.
    static func required(for files: [ModelFiles.File], alreadyDownloaded: [String: Int64]) -> Int64 {
        files.reduce(headroom) { $0 + max($1.bytes - (alreadyDownloaded[$1.name] ?? 0), 0) }
    }

    /// Free space for important data on the volume holding `url` (or its nearest existing parent), or nil when
    /// macOS can't say.
    static func available(at url: URL) -> Int64? {
        var folder = url
        while !FileManager.default.fileExists(atPath: folder.path), folder.path != "/" {
            folder = folder.deletingLastPathComponent()
        }
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
