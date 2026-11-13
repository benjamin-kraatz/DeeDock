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
        let inPlace = parent.appendingPathComponent(Self.inPlaceName(for: name, id: id))
        guard let folderVolume = Self.volumeIdentifier(of: parent) else { return inPlace }
        let candidate: URL
        // A folder can't be renamed into itself: dropping `~/Library/Caches` puts the home
        // staging folder inside the folder being deleted, so that case renames in place.
        if homeStaging.isSameOrDescendant(of: folder) {
            return inPlace
        } else if let homeVolume = Self.volumeIdentifier(ofNearestExisting: homeStaging), homeVolume.isEqual(folderVolume) {
            candidate = homeStaging
        } else if let root = Self.volumeRoot(of: parent) {
            candidate = root.appendingPathComponent(Self.volumeStagingFolderName, isDirectory: true)
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
        return candidate.appendingPathComponent(Self.stagedName(for: name, id: id))
    }

    /// Whether `staged` has one of the shapes ``stagedURL(for:id:)`` produces for a folder at
    /// `original` staged with `id`: `<homeStaging>/<id>-<name>`, `<ancestor>/.dokk-vapor/<id>-<name>`
    /// where the ancestor holds `original`, or the in-place sibling `.<name>.dokk-vapor-<id>`.
    ///
    /// Pure: compares lexically normalized paths and never touches the file system. A staged path
    /// with `.` or `..` components is refused outright, since what it names on disk can differ
    /// from its lexical form once a component is a link.
    ///
    /// Launch recovery deletes ledger entries recursively and without the Trash, so a corrupt or
    /// tampered ledger must not be able to name an arbitrary folder. Only paths this type could
    /// have produced for that entry pass.
    func isStagedPath(_ staged: URL, id: UUID, original: URL) -> Bool {
        let stagedPath = Self.normalizedPath(staged)
        guard staged.path == stagedPath else { return false }
        let originalURL = URL(fileURLWithPath: Self.normalizedPath(original))
        guard originalURL.path != "/" else { return false }
        let name = originalURL.lastPathComponent
        let stagedURL = URL(fileURLWithPath: stagedPath)
        let stagedParent = stagedURL.deletingLastPathComponent()
        let originalParent = originalURL.deletingLastPathComponent()
        let stagedLeaf = stagedURL.lastPathComponent

        if stagedLeaf == Self.inPlaceName(for: name, id: id) {
            return stagedParent.path == originalParent.path
        }
        guard stagedLeaf == Self.stagedName(for: name, id: id) else { return false }
        if stagedParent.path == Self.normalizedPath(homeStaging) { return true }
        // Another volume's staging folder: `<volume root>/.dokk-vapor`. The volume root is an
        // ancestor of the original folder, since a rename never crosses volumes.
        guard stagedParent.lastPathComponent == Self.volumeStagingFolderName else { return false }
        let root = stagedParent.deletingLastPathComponent().pathComponents
        let originalComponents = originalParent.pathComponents
        return originalComponents.count >= root.count && Array(originalComponents.prefix(root.count)) == root
    }

    /// Every staging folder Vapor may have used, for the drop policy's protection list.
    func knownStagingRoots() -> [URL] {
        var roots = [homeStaging]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        roots += volumes.map { $0.appendingPathComponent(Self.volumeStagingFolderName, isDirectory: true) }
        return roots
    }

    /// The staging folder's name at the root of a volume other than the home volume.
    static let volumeStagingFolderName = ".dokk-vapor"

    /// The name a folder gets inside a staging folder.
    static func stagedName(for name: String, id: UUID) -> String {
        "\(id.uuidString)-\(name)"
    }

    /// The name a folder gets when it is renamed in place, next to where it was.
    static func inPlaceName(for name: String, id: UUID) -> String {
        ".\(name).dokk-vapor-\(id.uuidString)"
    }

    /// Collapses `.`/`..` and a trailing slash without touching the file system, keeping a
    /// `/private` prefix (unlike `standardizedFileURL`).
    private static func normalizedPath(_ url: URL) -> String {
        url.standardized.path
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
