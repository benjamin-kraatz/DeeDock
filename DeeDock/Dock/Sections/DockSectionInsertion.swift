import CoreGraphics

/// Converts visible entry geometry back to persisted pin boundaries, excluding section controls.
enum DockSectionInsertion {
    static func index(point: CGPoint, scrollOffset: CGFloat, layout: DockGeometry.Layout,
                      entries: [DockRenderSlot], pinCount: Int, visibility: DockAppVisibility) -> Int? {
        guard visibility != .hidePinned else { return nil }
        let along = layout.edge.along(point) - scrollOffset
        let centers = layout.restingCenters
        if let controlIndex = entries.firstIndex(where: { $0.target == .group(.pinned) }), controlIndex < centers.count {
            if abs(along - centers[controlIndex]) <= layout.iconSize / 2 + layout.itemSpacing / 2 { return pinCount }
            if case .group(let control) = entries[controlIndex], !control.expanded { return nil }
        }
        let pins = entries.indices.filter { entries[$0].pin != nil && $0 < centers.count }
        if let running = entries.firstIndex(where: { !$0.isPinned }), running < centers.count,
           along > centers[running] - layout.iconSize / 2 - 4 { return nil }
        guard !pins.isEmpty else { return 0 }
        return pins.filter { along > centers[$0] }.count
    }
}
