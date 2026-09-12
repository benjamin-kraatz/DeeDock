import CoreGraphics

/// Sizes and clamps the transient panel in AppKit screen coordinates.
nonisolated enum WindowPeekGeometry {
    static let screenMargin: CGFloat = 12
    static let anchorGap: CGFloat = 10
    /// Two small panes, the divider, and the panel's padding must fit without horizontal clipping.
    static let minimumSplitWidth: CGFloat = 369

    static func splitSettings(_ settings: DockSettings) -> DockSettings {
        var result = settings
        result.windowPeekLayout = .grid
        // Both windows need visible names even when the ordinary layout hides captions.
        if result.windowPeekStyle == .minimal { result.windowPeekStyle = .captioned }
        return result
    }

    static func placement(anchor: WindowPeekAnchor, settings: DockSettings, count: Int, routingFiles: Bool = false,
                          split: Bool = false) -> WindowPeekPlacement {
        let card = cardSize(settings)
        let safeCount = max(1, count)
        let requested: CGSize
        if split {
            let pane = cardSize(splitSettings(settings))
            requested = CGSize(width: pane.width * 2 + 13 + 12, height: pane.height + 104)
        } else {
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
        }
        let available = anchor.visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        let size = CGSize(width: min(max(requested.width + 24, routingFiles ? 430 : 0), available.width),
                          height: min(requested.height + 24 + (routingFiles ? 140 : 0), available.height))
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

    /// Trims the sized panel down to the height the presented content actually needs.
    ///
    /// The panel is sized for a full card layout before anything is known about the windows, so a
    /// short body (loading, a permission fallback) would otherwise leave dead space. The edge the
    /// dock sits on decides which side stays put: the side nearest the icon, so the panel never
    /// drifts away from the tile it belongs to.
    static func fitted(_ placement: WindowPeekPlacement, contentHeight: CGFloat) -> CGRect {
        let height = min(max(contentHeight, 1), placement.frame.height)
        var frame = placement.frame
        frame.size.height = height
        switch placement.edge {
        case .bottom: break
        case .top: frame.origin.y = placement.frame.maxY - height
        case .left, .right: frame.origin.y = placement.frame.midY - height / 2
        }
        return frame
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
