import Foundation
import CoreGraphics

/// All geometry uses logical points; screen frames may have negative origins.
enum DockGeometry {
    /// Horizontal inset from the glass edge to the first and last icon squares.
    static let padding: CGFloat = 6
    /// Inset above the resting icon square and below its running indicator. Use nonnegative points.
    /// Lower this to make the glass shorter.
    static let verticalPadding: CGFloat = 6
    /// Gap between the image square and its running or selection indicator.
    static let indicatorSpacing: CGFloat = 0
    static let indicatorSize: CGFloat = 4
    /// Reserved even for apps that are not running, so their icons share the same baseline.
    static var indicatorAreaHeight: CGFloat { indicatorSpacing + indicatorSize }
    /// Inset of the glass surface from the panel bottom, in points.
    static let bottomMargin: CGFloat = 8
    static let separatorWidth: CGFloat = 16

    /// A resting canvas and viewport for one ordered collection of dock items.
    struct Layout {
        /// Base icon size before pointer magnification.
        let iconSize: CGFloat
        /// Maximum configured scale; Reduce Motion overrides it only at presentation time.
        let magnification: CGFloat
        /// Requested gap between adjacent items, in logical points.
        let itemSpacing: CGFloat
        /// Stable envelope accommodates the largest icon, running indicator, and hover label.
        var panelHeight: CGFloat {
            // The 48 points reserve room for the hover label above either the glass or a raised icon.
            // Increasing the inner padding must not clip either in the transparent panel envelope.
            let contentHeight = max(surfaceHeight, ceil(iconSize * magnification)
                                    + DockGeometry.verticalPadding + DockGeometry.indicatorAreaHeight)
            return max(128, contentHeight + DockGeometry.bottomMargin + 48)
        }
        /// Resting glass height. Magnification never changes it.
        var surfaceHeight: CGFloat {
            iconSize + DockGeometry.indicatorAreaHeight + 2 * DockGeometry.verticalPadding
        }
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
                let radius = (iconSize + itemSpacing) * 2.5
                let influence = max(0, 1 - distance / radius)
                return iconSize * (1 + (magnification - 1) * influence * influence)
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
                x += size + itemSpacing
                return center
            }
        }

        /// Glass bounds in top-left canvas coordinates. Hover affects width, never height.
        func surfaceFrame(sizes: [CGFloat]) -> CGRect {
            let width = contentWidth(sizes: sizes)
            let height = surfaceHeight
            return CGRect(x: (canvasWidth - width) / 2,
                          y: panelHeight - DockGeometry.bottomMargin - height,
                          width: width, height: height)
        }

        /// App-button bounds, including the running indicator, anchored to a fixed bottom baseline.
        /// These bounds may extend above the glass while remaining inside the panel envelope.
        func buttonFrame(centerX: CGFloat, size: CGFloat) -> CGRect {
            let height = size + DockGeometry.indicatorAreaHeight
            return CGRect(x: centerX - size / 2,
                          y: panelHeight - DockGeometry.bottomMargin - DockGeometry.verticalPadding - height,
                          width: size, height: height)
        }

        /// Bounds of the image square within its button, excluding the indicator row and any
        /// transparency supplied by the app's icon artwork. Shared by separators and drag gaps.
        func iconFrame(centerX: CGFloat, size: CGFloat) -> CGRect {
            let button = buttonFrame(centerX: centerX, size: size)
            return CGRect(x: button.minX, y: button.minY, width: size, height: size)
        }

        /// Width of the painted surface, including padding, spacing, and any section gap.
        func contentWidth(sizes: [CGFloat]) -> CGFloat {
            max(64, sizes.reduce(0, +) + CGFloat(max(0, sizes.count - 1)) * itemSpacing
                + DockGeometry.padding * 2 + (separatorIndex == nil ? 0 : DockGeometry.separatorWidth))
        }
    }

    /// Builds a resting layout, reducing icons to 32 points before allowing horizontal overflow.
    /// - Parameters:
    ///   - count: Total item count.
    ///   - favoriteCount: Number of leading pinned items, between zero and `count`.
    ///   - availableWidth: Chosen reference frame width in logical points.
    ///   - settings: Requested appearance; invalid values fall back to defaults.
    static func layout(count: Int, favoriteCount: Int, availableWidth: CGFloat, settings: DockSettings = .defaults) -> Layout {
        let settings = settings.normalized ?? .defaults
        let viewportLimit = max(64, availableWidth - 16)
        let separator: Int? = favoriteCount > 0 && favoriteCount < count ? favoriteCount : nil
        let itemSpacing = CGFloat(settings.itemSpacing)
        let extra = padding * 2 + CGFloat(max(0, count - 1)) * itemSpacing
            + (separator == nil ? 0 : separatorWidth)
        // Reserve the magnification envelope, rather than resizing the window on every mouse move.
        let size = min(CGFloat(settings.iconSize), max(32, (viewportLimit - extra) / CGFloat(max(1, count) + 2)))
        let restingWidth = max(64, CGFloat(count) * size + extra)
        // The quadratic falloff spans 2.5 resting spacings. Its summed influence is at most 1.8,
        // so two extra icon widths cover the supported maximum 2× scale, including the spring.
        let canvas = restingWidth + size * 2
        let viewport = min(viewportLimit, canvas)
        let initial = Layout(iconSize: size, magnification: CGFloat(settings.magnification), itemSpacing: itemSpacing, viewportWidth: viewport, canvasWidth: canvas,
                             restingCenters: [], separatorIndex: separator)
        let centers = initial.centers(sizes: Array(repeating: size, count: count))
        return Layout(iconSize: size, magnification: CGFloat(settings.magnification), itemSpacing: itemSpacing, viewportWidth: viewport, canvasWidth: canvas,
                      restingCenters: centers, separatorIndex: separator)
    }
}
