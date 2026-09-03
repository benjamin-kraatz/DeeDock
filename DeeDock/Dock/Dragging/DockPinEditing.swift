import Foundation
import CoreGraphics

/// Pure pin mutations. Insertion positions refer to the original list, before duplicates are removed.
nonisolated enum DockPinEditing {
    static func identity(_ pin: DockPin) -> String {
        switch pin {
        case .application(let reference): return "application:\(reference.id)"
        case .folder(let reference):
            let access = FolderResourceAccess(reference)
            defer { withExtendedLifetime(access) {} }
            return "folder:\(access.url.standardizedFileURL.path)"
        }
    }

    static func unique(_ pins: [DockPin]) -> [DockPin] {
        var seen = Set<String>()
        return pins.filter { seen.insert(identity($0)).inserted }
    }

    static func inserting(_ incoming: [DockPin], into pins: [DockPin], at index: Int) -> [DockPin] {
        let block = unique(incoming)
        let identities = Set(block.map(identity))
        let boundary = min(max(0, index), pins.count)
        let adjusted = pins.prefix(boundary).filter { !identities.contains(identity($0)) }.count
        var remaining = pins.filter { !identities.contains(identity($0)) }
        // Keep the established identity and bookmark when an existing pin is moved.
        let enriched = block.map { pin in
            pins.first { identity($0) == identity(pin) } ?? pin
        }
        remaining.insert(contentsOf: enriched, at: adjusted)
        return remaining
    }

    static func moving(_ id: String, in pins: [DockPin], by distance: Int) -> [DockPin] {
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
