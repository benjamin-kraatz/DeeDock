import Foundation

/// A folder, app, or file pinned to the sidebar's Favorites.
///
/// Folders filter the list to what is inside them and take drops (move, with Undo). Apps take drops
/// (open with). Files open on click. DOKK is not sandboxed, so a path is enough to find them again.
nonisolated struct FlixFavorite: Codable, Identifiable, Hashable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable { case folder, app, file }

    var id: UUID
    var kind: Kind
    /// Standardized absolute path.
    var path: String
    /// Finder's display name when it was added.
    var name: String

    init(id: UUID = UUID(), kind: Kind, path: String, name: String) {
        self.id = id
        self.kind = kind
        self.path = FlixPaths.standardized(path)
        self.name = name
    }

    var url: URL { URL(fileURLWithPath: path) }

    /// The favorite for `item`, or nil for a link, which cannot be a favorite.
    static func make(for item: FlixItem) -> FlixFavorite? {
        guard let path = item.path else { return nil }
        let kind: Kind = switch item.kind {
        case .folder: .folder
        case .app: .app
        default: .file
        }
        return FlixFavorite(kind: kind, path: path, name: item.name)
    }
}
