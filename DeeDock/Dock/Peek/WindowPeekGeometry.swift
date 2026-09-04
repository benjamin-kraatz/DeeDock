import CoreGraphics

/// Sizes and clamps the transient panel in AppKit screen coordinates.
nonisolated enum WindowPeekGeometry {
    static let screenMargin: CGFloat = 12
    static let anchorGap: CGFloat = 10

    static func placement(anchor: WindowPeekAnchor, settings: DockSettings, count: Int) -> WindowPeekPlacement {
        let card = cardSize(settings)
        let safeCount = max(1, count)
        let requested: CGSize
        switch settings.windowPeekLayout {
        case .list:
            requested = CGSize(width: card.width, height: card.height * CGFloat(min(safeCount, 4)) + 52)
        case .grid:
            let columns = min(safeCount, settings.windowPeekSize == .large ? 2 : 3)
            let rows = min(3, Int(ceil(Double(safeCount) / Double(columns))))
            requested = CGSize(width: card.width * CGFloat(columns) + CGFloat(max(0, columns - 1)) * 10,
                               height: card.height * CGFloat(rows) + CGFloat(max(0, rows - 1)) * 10 + 52)
        case .filmstrip:
            requested = CGSize(width: card.width * CGFloat(min(safeCount, 3)) + CGFloat(max(0, min(safeCount, 3) - 1)) * 10,
                               height: card.height + 52)
        }
        let available = anchor.visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        let size = CGSize(width: min(requested.width + 24, available.width),
                          height: min(requested.height + 24, available.height))
        let proposed: CGPoint
        switch anchor.edge {
        case .bottom:
            proposed = CGPoint(x: anchor.icon.midX - size.width / 2, y: anchor.icon.maxY + anchorGap)
        case .top:
            proposed = CGPoint(x: anchor.icon.midX - size.width / 2, y: anchor.icon.minY - anchorGap - size.height)
        case .left:
            proposed = CGPoint(x: anchor.icon.maxX + anchorGap, y: anchor.icon.midY - size.height / 2)
        case .right:
            proposed = CGPoint(x: anchor.icon.minX - anchorGap - size.width, y: anchor.icon.midY - size.height / 2)
        }
        let origin = CGPoint(x: min(max(proposed.x, available.minX), available.maxX - size.width),
                             y: min(max(proposed.y, available.minY), available.maxY - size.height))
        return WindowPeekPlacement(frame: CGRect(origin: origin, size: size), edge: anchor.edge)
    }

    static func cardSize(_ settings: DockSettings) -> CGSize {
        let thumbnail = settings.windowPeekSize.thumbnailSize
        return switch settings.windowPeekLayout {
        case .list: CGSize(width: max(360, thumbnail.width + 160), height: max(116, thumbnail.height + 16))
        case .grid, .filmstrip:
            CGSize(width: thumbnail.width, height: thumbnail.height + (settings.windowPeekStyle == .minimal ? 8 : 38))
        }
    }
}
