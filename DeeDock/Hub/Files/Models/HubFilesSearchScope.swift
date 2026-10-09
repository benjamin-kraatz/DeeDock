import Foundation

/// Where a Files search looks, chosen in the results' scope bar.
nonisolated enum HubFilesSearchScope: String, Codable, Sendable {
    /// Every indexed volume.
    case thisMac
    /// The active pane's folder and its subfolders.
    case currentFolder
}
