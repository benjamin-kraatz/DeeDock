import Foundation
import UniformTypeIdentifiers

extension LookoutHit {
    /// The hit as a Files item, so the preview column, Quick Look, the context menu, dragging and the file actions
    /// treat it like any other result. Built from what the index stored at its last sync, without touching the file.
    nonisolated var fileItem: HubFileItem {
        HubFileItem.lookout(path: path, isFolder: isFolder, size: isFolder ? nil : size, modified: modifiedDate)
    }

    /// A folder hit's best files as Files items (for its fanned stack), best first; empty for a file.
    nonisolated var topFileItems: [HubFileItem] {
        (folder?.topFiles ?? []).map { HubFileItem.lookout(path: $0, isFolder: false, size: nil, modified: nil) }
    }

    /// The modification date as a `Date`, when the index knows it.
    nonisolated var modifiedDate: Date? { modified.map(Date.init(timeIntervalSince1970:)) }
}

extension HubFileItem {
    /// An item for a path Lookout returned. The name is the file's own (extension included, as the index knows it)
    /// and the kind comes from the extension: no file-system read.
    nonisolated static func lookout(path: String, isFolder: Bool, size: Int64?, modified: Date?) -> HubFileItem {
        let url = HubFilesPath.normalized(URL(filePath: path, directoryHint: isFolder ? .isDirectory : .notDirectory))
        let type: UTType? = isFolder ? .folder : UTType(filenameExtension: url.pathExtension)
        return HubFileItem(
            url: url, name: url.lastPathComponent, isDirectory: isFolder, isPackage: false,
            isHidden: url.lastPathComponent.hasPrefix("."), contentType: type, byteSize: size, modified: modified,
            created: nil, volumeIdentifier: nil,
            kindDescription: isFolder ? String(localized: .hubFilesKindFolder) : type?.localizedDescription ?? "")
    }
}
