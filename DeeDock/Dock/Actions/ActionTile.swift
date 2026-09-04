import Foundation

/// A user-selected shortcut, addressed by UUID so renaming it in Shortcuts does not break the tile.
nonisolated struct ActionTile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
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
