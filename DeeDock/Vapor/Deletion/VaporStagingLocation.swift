import Foundation

/// Picks where a folder is renamed to when it's deleted. A rename never crosses volumes, because
/// that would turn the instant rename into a slow copy.
///
/// - On the home volume: `homeStaging`, normally `~/Library/Caches/DOKK/Vapor/staging`.
/// - On any other volume: `<volume root>/.dokk-vapor`.
/// - If that folder can't be created, or it turns out to be on a different volume (for example a
///   symlinked Caches folder), the folder is renamed in place to `.<name>.dokk-vapor-<uuid>`.
nonisolated struct VaporStagingLocation: Sendable {
    /// The staging folder on the home volume.
    let homeStaging: URL

    static var standard: VaporStagingLocation {
        VaporStagingLocation(homeStaging: URL.cachesDirectory.appending(path: "DOKK/Vapor/staging", directoryHint: .isDirectory))
    }

    /// The path `folder` should be renamed to. Creates the staging folder when needed.
    func stagedURL(for folder: URL, id: UUID) -> URL {
        let parent = folder.deletingLastPathComponent()
        let name = folder.lastPathComponent
        let inPlace = parent.appendingPathComponent(".\(name).dokk-vapor-\(id.uuidString)")
        guard let folderVolume = Self.volumeIdentifier(of: parent) else { return inPlace }
        let candidate: URL
        if let homeVolume = Self.volumeIdentifier(ofNearestExisting: homeStaging), homeVolume.isEqual(folderVolume) {
            candidate = homeStaging
        } else if let root = Self.volumeRoot(of: parent) {
            candidate = root.appendingPathComponent(".dokk-vapor", isDirectory: true)
        } else {
            return inPlace
        }
        do {
            try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        } catch {
            return inPlace
        }
        // Compare again on the real folder: a symlinked path can land on another volume.
        guard let stagingVolume = Self.volumeIdentifier(of: candidate), stagingVolume.isEqual(folderVolume) else {
            return inPlace
        }
        return candidate.appendingPathComponent("\(id.uuidString)-\(name)")
    }

    /// Every staging folder Vapor may have used, for the drop policy's protection list.
    func knownStagingRoots() -> [URL] {
        var roots = [homeStaging]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        roots += volumes.map { $0.appendingPathComponent(".dokk-vapor", isDirectory: true) }
        return roots
    }

    static func volumeIdentifier(of url: URL) -> (any NSObjectProtocol)? {
        (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? any NSObjectProtocol
    }

    private static func volumeIdentifier(ofNearestExisting url: URL) -> (any NSObjectProtocol)? {
        var current = url
        while true {
            if let identifier = volumeIdentifier(of: current) { return identifier }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    private static func volumeRoot(of url: URL) -> URL? {
        (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume
    }
}
