import AppKit
import Foundation

/// Immutable metadata loaded away from the main actor.
nonisolated struct FolderStackEntryReference: Equatable, Identifiable, Sendable {
    let url: URL
    let name: String
    let isFolder: Bool
    let contentType: String?
    let byteCount: Int64?
    let createdAt: Date?
    let modifiedAt: Date?
    var id: String { url.standardizedFileURL.path }

    init(url: URL, name: String, isFolder: Bool, contentType: String? = nil,
         byteCount: Int64? = nil, createdAt: Date? = nil, modifiedAt: Date? = nil) {
        self.url = url
        self.name = name
        self.isFolder = isFolder
        self.contentType = contentType
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    var semanticCandidate: SemanticStackCandidate {
        SemanticStackCandidate(
            id: id,
            name: name,
            kind: isFolder ? "folder" : (url.pathExtension.isEmpty ? "file" : url.pathExtension),
            contentType: contentType,
            isDirectory: isFolder,
            byteCount: byteCount,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            addedAt: nil
        )
    }
}

/// Main-actor presentation snapshot with a Finder-provided icon.
struct FolderStackEntry: Identifiable {
    let reference: FolderStackEntryReference
    let icon: NSImage
    var id: String { reference.id }
}

nonisolated enum FolderStackLoader {
    /// Reads only immediate, visible children. Packages and aliases remain leaf items.
    static func contents(of access: FolderResourceAccess, directory: URL? = nil) throws -> [FolderStackEntryReference] {
        guard access.isAvailable else { throw CocoaError(.fileNoSuchFile) }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isPackageKey, .isAliasFileKey, .isSymbolicLinkKey,
            .isHiddenKey, .localizedNameKey, .typeIdentifierKey, .fileSizeKey,
            .creationDateKey, .contentModificationDateKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(at: directory ?? access.url,
            includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        return try urls.compactMap { url in
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: keys)
            guard values.isHidden != true else { return nil }
            return FolderStackEntryReference(url: url.standardizedFileURL,
                name: values.localizedName ?? FileManager.default.displayName(atPath: url.path),
                isFolder: values.isDirectory == true && values.isPackage != true
                    && values.isAliasFile != true && values.isSymbolicLink != true,
                contentType: values.typeIdentifier,
                byteCount: values.fileSize.map(Int64.init),
                createdAt: values.creationDate,
                modifiedAt: values.contentModificationDate)
        }.sorted { lhs, rhs in
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
        }
    }
}
