import Foundation
import UniformTypeIdentifiers

/// Reads folder contents into `HubFileItem`s.
nonisolated enum HubDirectoryLister {
    /// Resource keys prefetched for every listed item, so building an item costs no extra I/O.
    static let resourceKeys: [URLResourceKey] = [
        .localizedNameKey, .isDirectoryKey, .isPackageKey, .isHiddenKey, .contentTypeKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        .contentModificationDateKey, .creationDateKey, .volumeIdentifierKey, .volumeUUIDStringKey
    ]

    /// Lists a folder's immediate children off the main actor.
    ///
    /// Runs on `VolumeReads` rather than the cooperative pool because a read on a wedged network
    /// share can block in the kernel. Hidden items are skipped unless `includeHidden` is true.
    /// - Throws: The file system's error when the folder cannot be read; `CancellationError` when
    ///   the calling task was cancelled before the result arrived.
    static func items(in folder: URL, includeHidden: Bool = false) async throws -> [HubFileItem] {
        let result: Result<[HubFileItem], Error> = await VolumeReads.run(qos: .userInitiated) {
            Result { try listSynchronously(folder, includeHidden: includeHidden) }
        }
        try Task.checkCancellation()
        return try result.get()
    }

    /// Synchronous listing. Blocks on file-system I/O; never call it on the main actor.
    static func listSynchronously(_ folder: URL, includeHidden: Bool) throws -> [HubFileItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: resourceKeys,
            options: includeHidden ? [] : [.skipsHiddenFiles])
        return urls.compactMap(item(at:))
    }

    /// Reads one item. Returns nil when the item no longer exists or cannot be read. Does file I/O.
    static func item(at url: URL) -> HubFileItem? {
        let url = url.standardizedFileURL
        guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else { return nil }
        let isPackage = values.isPackage ?? false
        let isDirectory = (values.isDirectory ?? false) && !isPackage
        let type = values.contentType
        let size: Int64? = isDirectory ? nil : Int64(
            values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        return HubFileItem(
            url: url,
            name: values.localizedName ?? FileManager.default.displayName(atPath: url.path),
            isDirectory: isDirectory,
            isPackage: isPackage,
            isHidden: values.isHidden ?? url.lastPathComponent.hasPrefix("."),
            contentType: type,
            byteSize: size,
            modified: values.contentModificationDate,
            created: values.creationDate,
            volumeIdentifier: volumeIdentifier(values),
            kindDescription: type?.localizedDescription ?? "")
    }

    /// A stable string per volume: the volume UUID, else the opaque volume identifier's description.
    static func volumeIdentifier(_ values: URLResourceValues) -> String? {
        if let uuid = values.volumeUUIDString { return uuid }
        if let identifier = values.volumeIdentifier { return String(describing: identifier) }
        return nil
    }

    /// The volume identifier of `url`, or of its nearest existing ancestor (a destination folder
    /// that does not exist yet still belongs to its parent's volume). Does file I/O.
    static func volumeIdentifier(of url: URL) -> String? {
        var current = url.standardizedFileURL
        while true {
            if let values = try? current.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeIdentifierKey]),
               let id = volumeIdentifier(values) {
                return id
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }
}
