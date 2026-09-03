import Foundation
import CoreGraphics

/// Pure pin mutations. Insertion positions refer to the original list, before duplicates are removed.
enum DockPinEditing {
    static func inserting(_ incoming: [ApplicationReference], into pins: [ApplicationReference], at index: Int) -> [ApplicationReference] {
        let block = DockOrdering.unique(incoming)
        let ids = Set(block.map(\.id))
        let boundary = min(max(0, index), pins.count)
        let adjusted = pins.prefix(boundary).filter { !ids.contains($0.id) }.count
        var remaining = pins.filter { !ids.contains($0.id) }
        // Prefer an existing bookmark when a running snapshot or a copied pin has no bookmark.
        let enriched = block.map { reference in
            reference.bookmarkData == nil ? (pins.first { $0.id == reference.id } ?? reference) : reference
        }
        remaining.insert(contentsOf: enriched, at: adjusted)
        return remaining
    }

    static func moving(_ id: String, in pins: [ApplicationReference], by distance: Int) -> [ApplicationReference] {
        guard let index = pins.firstIndex(where: { $0.id == id }), pins.indices.contains(index + distance) else { return pins }
        var result = pins
        let item = result.remove(at: index)
        result.insert(item, at: index + distance)
        return result
    }
}

/// Drag geometry is expressed in logical points, never backing pixels or magnified icon positions.
enum DockDragGeometry {
    static let startDistance: CGFloat = 5
    static let removalDistance: CGFloat = 64

    static func distance(_ point: CGPoint, outside rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    /// Source retention includes transparent label space. It holds visibility without blocking unpinning.
    /// Other dock destinations retain protection even when they reject a drop.
    static func protectsRemoval(at point: CGPoint, isSource: Bool, restingGlass: CGRect, retention: CGRect) -> Bool {
        (isSource ? restingGlass : retention).contains(point)
    }

    /// Returns a boundary in the persisted pinned section, or nil over the running-only section.
    static func insertion(point: CGPoint, scrollOffset: CGFloat, layout: DockGeometry.Layout, pinCount: Int) -> Int? {
        let x = layout.edge.along(point) - scrollOffset
        let centers = layout.restingCenters
        let count = min(pinCount, centers.count)
        if count == 0 { return 0 }
        if count < centers.count, x > centers[count] - layout.iconSize / 2 - 4 { return nil }
        return centers.prefix(count).filter { x > $0 }.count
    }

    /// Signed scroll velocity, active only within 28 points of a viewport edge.
    static func scrollVelocity(position: CGFloat, length: CGFloat) -> CGFloat {
        if position < 28 { return -240 * max(0, min(1, (28 - position) / 28)) }
        if position > length - 28 { return 240 * max(0, min(1, (position - length + 28) / 28)) }
        return 0
    }
}

/// Completion evidence is separate from AppKit's operation result, which also reports Escape as failure.
struct DockDragCompletion {
    var released = false
    var cancelled = false
    var committed = false

    func shouldUnpin(isPinned: Bool, distance: CGFloat, overDock: Bool) -> Bool {
        released && !cancelled && !committed && isPinned && !overDock && distance >= DockDragGeometry.removalDistance
    }
}
