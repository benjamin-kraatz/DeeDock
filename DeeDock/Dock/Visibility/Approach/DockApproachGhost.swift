import AppKit

/// A still outline of the resting dock that the approach glow fades in over its final points.
///
/// The ghost shows where the hidden dock will appear and how large it is. Every icon is drawn as a
/// monochrome imprint whatever the dock's icon style, so its rects and images are a snapshot taken
/// when the dock lays out, not live tile state. The controller stores it in AppKit screen
/// coordinates and converts it to the glow panel's top-left view coordinates before drawing.
struct DockApproachGhost: Equatable {
    struct Tile: Equatable {
        var frame: CGRect
        /// The tile's native artwork, or nil for tiles drawn from symbols, which show as a blank slot.
        var icon: NSImage?
    }

    /// The resting glass, or nil when the dock draws no background.
    var glass: CGRect?
    var cornerRadius: CGFloat
    var tiles: [Tile]

    /// The union of the glass and every tile, or `.null` for an empty ghost.
    var bounds: CGRect { tiles.reduce(glass ?? .null) { $0.union($1.frame) } }

    /// The same ghost with every rect passed through `transform`.
    func converted(_ transform: (CGRect) -> CGRect) -> DockApproachGhost {
        DockApproachGhost(glass: glass.map(transform), cornerRadius: cornerRadius,
                          tiles: tiles.map { Tile(frame: transform($0.frame), icon: $0.icon) })
    }

    /// The resting dock for `slots`, in AppKit screen coordinates.
    ///
    /// Uses resting centers and sizes, so magnification never reaches the ghost. An overflowing dock
    /// is shifted by its scroll offset at snapshot time, and only tiles fully inside the viewport are
    /// kept: a partly scrolled-out icon would otherwise be squeezed into its clipped rect.
    ///
    /// - Parameters:
    ///   - slots: The rendered slots in layout order; insertion gaps are skipped.
    ///   - restingFrame: The resting panel frame the layout's canvas coordinates belong to.
    ///   - showsGlass: Whether the dock draws its background.
    static func resting(slots: [DockRenderSlot], layout: DockGeometry.Layout, restingFrame: CGRect,
                        scrollOffset: CGFloat, showsGlass: Bool, cornerRadius: CGFloat) -> DockApproachGhost {
        let edge = layout.edge
        let shift = edge.isVertical ? CGSize(width: 0, height: scrollOffset) : CGSize(width: scrollOffset, height: 0)
        let viewport = CGRect(origin: .zero, size: layout.viewportSize).insetBy(dx: -1, dy: -1)
        let tiles: [Tile] = zip(slots, layout.restingCenters).compactMap { slot, center in
            if case .gap = slot { return nil }
            let frame = layout.iconFrame(centerAlong: center, size: layout.iconSize).offsetBy(dx: shift.width, dy: shift.height)
            guard viewport.contains(frame) else { return nil }
            return Tile(frame: DockEdge.screenRect(frame, in: restingFrame), icon: slot.ghostIcon)
        }
        var glass: CGRect?
        if showsGlass {
            let rect = DockGeometry.restingGlass(frame: restingFrame, layout: layout, scrollOffset: scrollOffset)
            if !rect.isEmpty { glass = rect }
        }
        let radius = glass.map { min(cornerRadius, min($0.width, $0.height) / 2) } ?? 0
        return DockApproachGhost(glass: glass, cornerRadius: radius, tiles: tiles)
    }
}

private extension DockRenderSlot {
    /// Artwork for the ghost imprint. Tiles drawn from SF Symbols or vector marks have none.
    var ghostIcon: NSImage? {
        switch self {
        case .app(let item): item.icon
        case .folder(let item): item.icon
        case .trash(let item): item.icon
        case .shelf(let item): item.icon
        case .sessionCapsules(let item): item.icon
        case .sessionCapsule(let item): item.icon
        case .volume(let item): item.icon
        case .launcher, .focus, .action, .melt, .group, .notificationFeed, .harbor, .update, .gap: nil
        }
    }
}
