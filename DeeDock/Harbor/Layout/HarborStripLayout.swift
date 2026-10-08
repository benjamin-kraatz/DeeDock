import CoreGraphics
import Foundation

/// Where the running-apps strip and each of its tiles sit on a display, in the panel's
/// top-left, y-down coordinates.
///
/// The strip is laid out explicitly rather than with a stack so that every tile has a frame to
/// animate to from the dock's own geometry (``HarborDockSeed``) and back again.
nonisolated struct HarborStripLayout: Equatable, Sendable {
    /// One tile: the icon square and the label slot under it.
    nonisolated struct Tile: Equatable, Sendable {
        let icon: CGRect
        let label: CGRect
    }

    /// A tile to place: its stable identifier and whether a gap separates it from the one before.
    nonisolated struct Item: Equatable, Sendable {
        let id: String
        var gapBefore = false
    }

    nonisolated enum Metrics {
        static let icon: CGFloat = 52
        /// Space on either side of an icon along the strip.
        static let margin: CGFloat = 4
        /// Padding at the strip's ends along its length.
        static let endPadding: CGFloat = 8
        /// Padding on the far side from the display edge, above the icons.
        static let leadingDepth: CGFloat = 10
        static let labelHeight: CGFloat = 14
        static let labelGap: CGFloat = 9
        static let labelWidth: CGFloat = 76
        /// Extra space before a tile that sits apart, like the Harbor tile.
        static let sectionGap: CGFloat = 10
        static let cornerRadius: CGFloat = 24
        /// Distance from the display edge; the menu bar adds to it for a top dock.
        static let edgeInset: CGFloat = 8
        static let menuBarAllowance: CGFloat = 24
        /// Icon-to-icon distance on a vertical strip, where each label sits under its icon.
        static var verticalPitch: CGFloat { icon + labelGap + labelHeight + 8 }
    }

    let glass: CGRect
    let cornerRadius: CGFloat
    let tiles: [String: Tile]

    /// Lays the strip along `edge`, centered on the display.
    static func place(_ items: [Item], edge: DockEdge, displaySize: CGSize) -> HarborStripLayout {
        let gaps = CGFloat(items.filter(\.gapBefore).count) * Metrics.sectionGap
        var tiles: [String: Tile] = [:]
        let vertical: Bool = switch edge { case .left, .right: true; case .top, .bottom: false }
        if vertical {
            let pitch = Metrics.verticalPitch
            let length = 2 * Metrics.endPadding + CGFloat(items.count) * pitch + gaps
            let left: Bool = if case .left = edge { true } else { false }
            let glass = CGRect(x: left ? Metrics.edgeInset : displaySize.width - Metrics.edgeInset - HarborStripMetrics.thickness,
                               y: (displaySize.height - length) / 2,
                               width: HarborStripMetrics.thickness, height: length)
            var y = glass.minY + Metrics.endPadding
            for item in items {
                if item.gapBefore { y += Metrics.sectionGap }
                let icon = CGRect(x: glass.midX - Metrics.icon / 2, y: y + Metrics.margin, width: Metrics.icon, height: Metrics.icon)
                tiles[item.id] = Tile(icon: icon, label: labelFrame(under: icon))
                y += pitch
            }
            return HarborStripLayout(glass: glass, cornerRadius: Metrics.cornerRadius, tiles: tiles)
        }
        let pitch = Metrics.icon + 2 * Metrics.margin
        let length = 2 * Metrics.endPadding + CGFloat(items.count) * pitch + gaps
        let top: Bool = if case .top = edge { true } else { false }
        let inset = Metrics.edgeInset + (top ? Metrics.menuBarAllowance : 0)
        let glass = CGRect(x: (displaySize.width - length) / 2,
                           y: top ? inset : displaySize.height - inset - HarborStripMetrics.thickness,
                           width: length, height: HarborStripMetrics.thickness)
        var x = glass.minX + Metrics.endPadding
        for item in items {
            if item.gapBefore { x += Metrics.sectionGap }
            let icon = CGRect(x: x + Metrics.margin, y: glass.minY + Metrics.leadingDepth, width: Metrics.icon, height: Metrics.icon)
            tiles[item.id] = Tile(icon: icon, label: labelFrame(under: icon))
            x += pitch
        }
        return HarborStripLayout(glass: glass, cornerRadius: Metrics.cornerRadius, tiles: tiles)
    }

    private static func labelFrame(under icon: CGRect) -> CGRect {
        CGRect(x: icon.midX - Metrics.labelWidth / 2, y: icon.maxY + Metrics.labelGap,
               width: Metrics.labelWidth, height: Metrics.labelHeight)
    }
}
