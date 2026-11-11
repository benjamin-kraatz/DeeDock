import Foundation

/// Measures a folder for the orb. Implementations must honour task cancellation.
nonisolated protocol VaporMeasuring: Sendable {
    func measure(_ url: URL) async -> VaporMeasurement
}

/// Sums allocated sizes and counts files on a utility-priority thread, off the main actor.
///
/// Allocated size (`totalFileAllocatedSize`) is what deleting gives back, so it is what the panel
/// and "Freed …" report. Symbolic links count with their own small size and are not followed.
nonisolated struct VaporFileMeasurer: VaporMeasuring {
    @concurrent func measure(_ url: URL) async -> VaporMeasurement {
        Self.measureSynchronously(url)
    }

    /// The blocking walk. Returns `.unreadable` when the folder itself can't be listed, and
    /// `.pending` when cancelled, so a cancelled result is never mistaken for a real size.
    static func measureSynchronously(_ url: URL) -> VaporMeasurement {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil else { return .unreadable }
        var bytes: Int64 = 0
        var files = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: []) { _, _ in
            // Skip what can't be read and keep going: a partly readable cache still has a size.
            true
        }
        var visited = 0
        while let item = enumerator?.nextObject() as? URL {
            visited += 1
            if visited % 512 == 0, Task.isCancelled { return .pending }
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            bytes += Int64(size)
            if values.isDirectory != true || values.isSymbolicLink == true { files += 1 }
        }
        if Task.isCancelled { return .pending }
        return .measured(bytes: bytes, files: files)
    }
}
