import Foundation
import UniformTypeIdentifiers

/// One file-system item as the Hub shows it.
///
/// A snapshot read from resource values; it never refreshes itself. Listing again (after a
/// `HubDirectoryWatcher` change) produces new values. Identity is the standardized file URL.
nonisolated struct HubFileItem: Identifiable, Hashable, Sendable {
    /// Standardized file URL. Also the identity.
    let url: URL
    var id: URL { url }
    /// Localized display name with `FileManager.displayName(atPath:)` semantics (hidden extensions stay hidden).
    let name: String
    /// True for folders. False for packages (apps, bundles), which behave like files.
    let isDirectory: Bool
    /// True for packages such as `.app` bundles.
    let isPackage: Bool
    /// True for dot-files and items flagged hidden.
    let isHidden: Bool
    /// The item's uniform type, when known.
    let contentType: UTType?
    /// Allocated size on disk. Nil for folders.
    let byteSize: Int64?
    /// Content modification date.
    let modified: Date?
    /// Creation date.
    let created: Date?
    /// Stable per volume. Two items with equal identifiers live on the same volume (move vs. copy).
    let volumeIdentifier: String?
    /// Localized kind ("PDF document"), from `UTType.localizedDescription`.
    let kindDescription: String
}
