import CoreGraphics
import Foundation

/// Selection arithmetic for the Shelf panel, independent of SwiftUI and AppKit.
///
/// The panel supports the selection gestures a Finder list does: click to replace, Command to
/// toggle, Shift to extend from an anchor, and a rubber band swept across empty space.
nonisolated enum ShelfSelection {
    /// The rectangle swept between a press and the current pointer, in either direction.
    static func band(from origin: CGPoint, to point: CGPoint) -> CGRect {
        CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y),
               width: abs(point.x - origin.x), height: abs(point.y - origin.y))
    }

    /// Every row the band touches. A zero-height band still selects the row it crosses.
    static func within(_ band: CGRect, frames: [UUID: CGRect]) -> Set<UUID> {
        Set(frames.filter { $0.value.intersects(band) || band.intersects($0.value) }.keys)
    }

    /// Command-click adds or removes one row without disturbing the rest.
    static func toggling(_ selection: Set<UUID>, _ id: UUID) -> Set<UUID> {
        var next = selection
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        return next
    }

    /// Shift-click selects everything between the anchor and the clicked row, in either order.
    /// Without a usable anchor it falls back to the clicked row alone.
    static func extending(from anchor: UUID?, to id: UUID, in order: [UUID]) -> Set<UUID> {
        guard let anchor, anchor != id,
              let start = order.firstIndex(of: anchor), let end = order.firstIndex(of: id) else { return [id] }
        return Set(order[min(start, end)...max(start, end)])
    }

    /// The items a drag carries: the whole selection when the pressed row belongs to it,
    /// otherwise just that row.
    static func dragging(_ id: UUID, selection: Set<UUID>) -> Set<UUID> {
        selection.contains(id) ? selection : [id]
    }

    /// Drops rows that no longer exist, so a removal elsewhere cannot leave a phantom selection.
    static func retained(_ selection: Set<UUID>, in order: [UUID]) -> Set<UUID> {
        selection.intersection(order)
    }
}
