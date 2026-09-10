import Foundation

/// Visual health of one greenhouse plant. Wilt is a discovery result, not a run failure.
nonisolated enum ShortcutGreenhouseHealth: Equatable, Sendable {
    case healthy
    case wilted

    /// Wilt only after Shortcuts have been listed and this identifier is absent.
    /// Before discovery, a pin stays healthy so chrome does not flash wilted on launch.
    static func resolve(discovered: Bool, isAvailable: Bool) -> Self {
        discovered && !isAvailable ? .wilted : .healthy
    }

    var title: LocalizedStringResource {
        switch self {
        case .healthy: .greenhouseHealthy
        case .wilted: .greenhouseWilted
        }
    }
}

/// One pinned shortcut drawn as a plant. Watering uses ``ActionTilesController/water(_:)``.
nonisolated struct ShortcutGreenhousePlant: Equatable, Identifiable, Sendable {
    let tile: ActionTile
    let status: ActionTileStatus
    let health: ShortcutGreenhouseHealth

    var id: UUID { tile.id }
    var canWater: Bool { !status.busy }

    init(tile: ActionTile, status: ActionTileStatus, health: ShortcutGreenhouseHealth) {
        self.tile = tile
        self.status = status
        self.health = health
    }

    init(tile: ActionTile, status: ActionTileStatus, discovered: Bool, availableIDs: Set<UUID>) {
        self.tile = tile
        self.status = status
        self.health = .resolve(discovered: discovered, isAvailable: availableIDs.contains(tile.id))
    }
}
