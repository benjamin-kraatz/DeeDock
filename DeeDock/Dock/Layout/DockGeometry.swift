import Foundation
import CoreGraphics

/// All geometry uses logical points; screen frames may have negative origins.
enum DockGeometry {
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 12
    /// Fixed envelope includes magnification and labels, avoiding pointer-driven window resizing.
    static let panelHeight: CGFloat = 168
    /// Inset of the glass surface from the panel bottom, in points.
    static let bottomMargin: CGFloat = 8
    static let separatorWidth: CGFloat = 16

    /// A resting canvas and viewport for one ordered collection of dock items.
    struct Layout {
        /// Base icon size before pointer magnification.
        let iconSize: CGFloat
        /// Visible width, capped to the available display area.
        let viewportWidth: CGFloat
        /// Scrollable width, including the reserved magnification envelope.
        let canvasWidth: CGFloat
        /// Stable canvas-space x positions; never replace these with animated positions.
        let restingCenters: [CGFloat]
        /// Index of the first running-only item, or nil when one section is empty.
        let separatorIndex: Int?

        /// Computes icon dimensions from a canvas-space pointer x coordinate.
        /// A nil pointer or Reduce Motion returns resting sizes.
        func sizes(pointerX: CGFloat?, reduceMotion: Bool) -> [CGFloat] {
            restingCenters.map { center in
                guard let pointerX, !reduceMotion else { return iconSize }
                // Measure against resting centers so moving icons do not chase the pointer.
                let distance = abs(pointerX - center)
                let radius = (iconSize + DockGeometry.spacing) * 2.5
                let influence = max(0, 1 - distance / radius)
                return iconSize * (1 + 0.4 * influence * influence)
            }
        }

        /// Positions the supplied item sizes while preserving spacing and the section gap.
        /// - Parameter sizes: One size per item, in the layout’s original order.
        func centers(sizes: [CGFloat]) -> [CGFloat] {
            let width = contentWidth(sizes: sizes)
            var x = (canvasWidth - width) / 2 + DockGeometry.padding
            return sizes.enumerated().map { index, size in
                if index == separatorIndex { x += DockGeometry.separatorWidth }
                let center = x + size / 2
                x += size + DockGeometry.spacing
                return center
            }
        }

        /// Width of the painted surface, including padding, spacing, and any section gap.
        func contentWidth(sizes: [CGFloat]) -> CGFloat {
            max(64, sizes.reduce(0, +) + CGFloat(max(0, sizes.count - 1)) * DockGeometry.spacing
                + DockGeometry.padding * 2 + (separatorIndex == nil ? 0 : DockGeometry.separatorWidth))
        }
    }

    /// Builds a resting layout, reducing icons to 32 points before allowing horizontal overflow.
    /// - Parameters:
    ///   - count: Total item count.
    ///   - favoriteCount: Number of leading pinned items, between zero and `count`.
    ///   - availableWidth: Display usable width in logical points.
    static func layout(count: Int, favoriteCount: Int, availableWidth: CGFloat) -> Layout {
        let viewportLimit = max(64, availableWidth - 16)
        let separator: Int? = favoriteCount > 0 && favoriteCount < count ? favoriteCount : nil
        let extra = padding * 2 + CGFloat(max(0, count - 1)) * spacing
            + (separator == nil ? 0 : separatorWidth)
        // Reserve the magnification envelope, rather than resizing the window on every mouse move.
        let size = min(48, max(32, (viewportLimit - extra) / CGFloat(max(1, count) + 2)))
        let restingWidth = max(64, CGFloat(count) * size + extra)
        let canvas = restingWidth + size * 2
        let viewport = min(viewportLimit, canvas)
        let initial = Layout(iconSize: size, viewportWidth: viewport, canvasWidth: canvas,
                             restingCenters: [], separatorIndex: separator)
        let centers = initial.centers(sizes: Array(repeating: size, count: count))
        return Layout(iconSize: size, viewportWidth: viewport, canvasWidth: canvas,
                      restingCenters: centers, separatorIndex: separator)
    }

    /// Centers a panel within a display’s usable frame without assuming a zero screen origin.
    static func panelFrame(visibleFrame: CGRect, width: CGFloat) -> CGRect {
        // The glass starts bottomMargin above the panel bottom, at visibleFrame.minY + 8.
        CGRect(x: visibleFrame.midX - width / 2, y: visibleFrame.minY,
               width: width, height: panelHeight)
    }
}
