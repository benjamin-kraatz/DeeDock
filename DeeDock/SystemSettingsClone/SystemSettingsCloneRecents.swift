import Foundation

/// Most-recently-opened pane IDs, stored as one comma-separated `@AppStorage` string.
///
/// Only catalog IDs are stored, never System Settings values. Unknown IDs from an older
/// catalog are dropped when read.
enum SystemSettingsCloneRecents {
    static let storageKey = "systemSettingsClone.recentPaneIDs"
    static let limit = 8

    static func decode(_ stored: String) -> [String] {
        stored.split(separator: ",").map(String.init)
    }

    /// Moves `paneID` to the front and trims the list to `limit`.
    static func recording(_ paneID: String, in stored: String) -> String {
        let updated = [paneID] + decode(stored).filter { $0 != paneID }
        return updated.prefix(limit).joined(separator: ",")
    }

    /// Recents first, then popular panes, without duplicates, `limit` items at most.
    static func quickAccess(from stored: String) -> [SystemSettingsClonePane] {
        var seen = Set<String>()
        let ids = decode(stored) + SystemSettingsDeepLinkCatalog.popularPaneIDs
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return SystemSettingsDeepLinkCatalog.pane(id: id)
        }
        .prefix(limit)
        .map { $0 }
    }
}
