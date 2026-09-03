import AppKit
import Foundation

/// Immutable metadata loaded away from the main actor.
nonisolated struct FolderStackEntryReference: Equatable, Identifiable, Sendable {
    let url: URL
    let name: String
    let isFolder: Bool
    var id: String { url.standardizedFileURL.path }
}

/// Main-actor presentation snapshot with a Finder-provided icon.
struct FolderStackEntry: Identifiable {
    let reference: FolderStackEntryReference
    let icon: NSImage
    var id: String { reference.id }
}

nonisolated enum FolderStackLoader {
    /// Reads only immediate, visible children. Packages and aliases remain leaf items.
    static func contents(of access: FolderResourceAccess) throws -> [FolderStackEntryReference] {
        guard access.isAvailable else { throw CocoaError(.fileNoSuchFile) }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isAliasFileKey,
                                         .isSymbolicLinkKey, .isHiddenKey, .localizedNameKey]
        let urls = try FileManager.default.contentsOfDirectory(at: access.url,
            includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        return try urls.compactMap { url in
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: keys)
            guard values.isHidden != true else { return nil }
            return FolderStackEntryReference(url: url.standardizedFileURL,
                name: values.localizedName ?? FileManager.default.displayName(atPath: url.path),
                isFolder: values.isDirectory == true && values.isPackage != true
                    && values.isAliasFile != true && values.isSymbolicLink != true)
        }.sorted { lhs, rhs in
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
        }
    }
}
