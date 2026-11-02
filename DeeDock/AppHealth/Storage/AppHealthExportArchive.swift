import Foundation

/// `manifest.json` at the root of an export archive.
nonisolated struct AppHealthExportManifest: Codable, Sendable, Equatable {
    /// The record schema version of the files (`AppHealthRecord.schemaVersion`).
    var schema: Int
    /// Unix seconds.
    var exportedAt: Double
    /// DOKK's marketing version and build, such as `0.24.3 (74)`.
    var dokkVersion: String
    /// The `.jsonl` file names in the archive, oldest first.
    var files: [String]
    /// Seconds between ticks.
    var sampleInterval: Int

    init(exportedAt: Date, dokkVersion: String, files: [String] = [], sampleInterval: Int) {
        schema = AppHealthRecord.schemaVersion
        self.exportedAt = AppHealthRounding.timestamp(exportedAt)
        self.dokkVersion = dokkVersion
        self.files = files
        self.sampleInterval = sampleInterval
    }
}

/// Why an export did not produce an archive.
nonisolated enum AppHealthExportError: Error, Equatable {
    /// There were no files to export.
    case noData
    /// Zipping, copying, or moving failed.
    case failed
}

/// Builds the export archive: copies the files and a manifest into a staging folder, zips it with
/// `NSFileCoordinator`'s public `.forUploading` option, and moves the zip to the destination.
///
/// Synchronous and file-system heavy; the record store calls it on its own actor, never on the main actor.
nonisolated enum AppHealthExportArchive {
    /// The folder name inside the archive.
    static let folderName = "DOKK App Health"

    static func write(files: [URL], manifest: AppHealthExportManifest, to destination: URL) throws {
        guard !files.isEmpty else { throw AppHealthExportError.noData }
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appending(path: "DOKK-AppHealth-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: staging) }
        let folder = staging.appending(path: folderName, directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            for file in files {
                try fileManager.copyItem(at: file, to: folder.appending(path: file.lastPathComponent))
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(manifest).write(to: folder.appending(path: "manifest.json"), options: .atomic)
        } catch {
            throw AppHealthExportError.failed
        }

        // `.forUploading` hands the accessor a temporary zip of the folder that is deleted when the accessor
        // returns, so the zip is copied out inside it.
        let zip = staging.appending(path: "export.zip")
        var coordinationError: NSError?
        var copyError: (any Error)?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading,
                                       error: &coordinationError) { zipped in
            do { try fileManager.copyItem(at: zipped, to: zip) } catch { copyError = error }
        }
        guard coordinationError == nil, copyError == nil, fileManager.fileExists(atPath: zip.path) else {
            throw AppHealthExportError.failed
        }
        do {
            // The save panel already confirmed replacing an existing file. `replaceItemAt` needs both items on one
            // volume and the destination may be an external or network drive, so the zip is first moved next to it.
            if fileManager.fileExists(atPath: destination.path) {
                let nearby = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                 appropriateFor: destination, create: true)
                defer { try? fileManager.removeItem(at: nearby) }
                let staged = nearby.appending(path: destination.lastPathComponent)
                try fileManager.moveItem(at: zip, to: staged)
                _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
            } else {
                try fileManager.moveItem(at: zip, to: destination)
            }
        } catch {
            throw AppHealthExportError.failed
        }
    }
}
