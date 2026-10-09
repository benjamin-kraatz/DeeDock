import Foundation

/// What a Files pane shows: a folder, or the virtual Recents list.
nonisolated enum HubFilesLocation: Hashable, Codable, Sendable {
    /// Recently used files from Spotlight. Has no parent and accepts no drops.
    case recents
    /// A folder on any mounted volume. The URL is normalized with `HubFilesPath.normalized(_:)`.
    case folder(URL)

    /// The folder URL, or nil for Recents.
    var folderURL: URL? {
        if case .folder(let url) = self { url } else { nil }
    }

    /// A folder location with a normalized URL, so equal paths compare equal.
    static func folder(normalizing url: URL) -> HubFilesLocation {
        .folder(HubFilesPath.normalized(url))
    }
}
