import Foundation

/// The Flix Files dock tile. It carries no state; the tile reads the shared `FlixTileState`, so a
/// new item redraws one tile instead of rebuilding every dock.
struct FlixDockItem: Identifiable, Equatable {
    var id: String { DockEntryID.flix.hitID }
}
