import Foundation

/// A user-selected shortcut, addressed by UUID so renaming it in Shortcuts does not break the tile.
nonisolated struct ActionTile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    /// User-declared file-input intent. Discovery cannot prove what a Shortcut accepts.
    var acceptsFiles: Bool

    init(id: UUID, name: String, acceptsFiles: Bool = false) {
        self.id = id
        self.name = name
        self.acceptsFiles = acceptsFiles
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        acceptsFiles = try values.decodeIfPresent(Bool.self, forKey: .acceptsFiles) ?? false
    }
}

/// Persisted tiles are app-wide, ordered, and independent of display appearance or Dock Modes.
nonisolated struct ActionTilesDocument: Codable {
    var version = 1
    var tiles: [ActionTile] = []
}

/// Transient execution state, never persisted or replayed after launch.
enum ActionTileStatus: Equatable {
    case idle, running, succeeded, failed(String)
    var busy: Bool { self == .running }
    var title: String {
        switch self {
        case .idle: String(localized: .actionsReady)
        case .running: String(localized: .actionsRunning)
        case .succeeded: String(localized: .actionsSucceeded)
        case .failed(let message): message
        }
    }
}

struct ActionDockItem {
    let tile: ActionTile
    let status: ActionTileStatus
}
