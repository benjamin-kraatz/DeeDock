import CoreGraphics

extension DockGeometry {
    /// Chooses the full display or the area left by reserved system UI.
    static func referenceFrame(screenFrame: CGRect, visibleFrame: CGRect, settings: DockSettings) -> CGRect {
        settings.positionReference == .usableDesktop ? visibleFrame : screenFrame
    }

    /// Anchors glass to the requested edge. Only the transparent outer margin may leave the reference.
    /// Along-axis coordinates increase left-to-right below and top-to-bottom beside the display.
    static func panelFrame(referenceFrame: CGRect, layout: Layout, settings: DockSettings) -> CGRect {
        let settings = settings.normalized ?? .defaults
        let edge = settings.edge
        let length = edge.length(of: referenceFrame.size)
        let depth = edge.depth(of: referenceFrame.size)
        let resting = layout.contentLength(sizes: Array(repeating: layout.iconSize, count: layout.restingCenters.count))
        let inset = max(0, (layout.viewportLength - resting) / 2)
        let aligned: CGFloat
        switch settings.alignment {
        case .start: aligned = 8 - inset
        case .center: aligned = (length - layout.viewportLength) / 2
        case .end: aligned = length - 8 - layout.viewportLength + inset
        }
        let along = min(max(aligned + CGFloat(settings.alongEdgeOffset), 8), max(8, length - 8 - layout.viewportLength))
        let distance = min(max(CGFloat(settings.edgeDistance) - outerMargin, -outerMargin), max(-outerMargin, depth - layout.panelDepth))
        switch edge {
        case .bottom:
            return CGRect(x: referenceFrame.minX + along, y: referenceFrame.minY + distance,
                          width: layout.viewportLength, height: layout.panelDepth)
        case .left:
            return CGRect(x: referenceFrame.minX + distance, y: referenceFrame.maxY - along - layout.viewportLength,
                          width: layout.panelDepth, height: layout.viewportLength)
        case .right:
            return CGRect(x: referenceFrame.maxX - distance - layout.panelDepth, y: referenceFrame.maxY - along - layout.viewportLength,
                          width: layout.panelDepth, height: layout.viewportLength)
        }
    }

    /// Resting visible glass, shared by activation, diagrams, and drag removal bounds.
    static func restingGlass(frame: CGRect, layout: Layout, scrollOffset: CGFloat = 0) -> CGRect {
        let offset = layout.edge.isVertical ? CGSize(width: 0, height: scrollOffset) : CGSize(width: scrollOffset, height: 0)
        let rect = layout.surfaceFrame(sizes: layout.sizes(pointerAlong: nil, reduceMotion: true))
            .offsetBy(dx: offset.width, dy: offset.height)
            .intersection(CGRect(origin: .zero, size: layout.viewportSize))
        return DockEdge.screenRect(rect, in: frame)
    }
}
