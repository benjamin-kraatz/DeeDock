import Foundation
import CoreGraphics

/// All geometry uses logical points; screen frames may have negative origins.
enum DockGeometry {
    /// Along-axis inset from the glass edge to the first and last icon squares.
    static let padding: CGFloat = 6
    /// Inset on both sides of the icon and indicator across the glass thickness.
    static let crossPadding: CGFloat = 6
    /// Gap between the image square and its running or selection indicator.
    static let indicatorSpacing: CGFloat = 0
    static let indicatorSize: CGFloat = 4
    /// Reserved even for apps that are not running, so their icons share the outer baseline.
    static var indicatorAreaDepth: CGFloat { indicatorSpacing + indicatorSize }
    /// Inset of the glass surface from the panel outer edge, in points.
    static let outerMargin: CGFloat = 8
    static let separatorLength: CGFloat = 16

    /// A resting canvas and viewport for one ordered collection of dock items.
    struct Layout {
        /// Base icon size before pointer magnification.
        let iconSize: CGFloat
        /// Maximum configured scale; Reduce Motion overrides it only at presentation time.
        let magnification: CGFloat
        /// Requested gap between adjacent items, in logical points.
        let itemSpacing: CGFloat
        let edge: DockEdge
        let availableDepth: CGFloat
        /// Stable envelope accommodates the largest icon, running indicator, and hover label.
        var panelDepth: CGFloat {
            // The 48 points reserve room for the hover label inward of the glass or a raised icon.
            // Increasing the inner padding must not clip either in the transparent panel envelope.
            let contentHeight = max(surfaceDepth, ceil(iconSize * magnification)
                                    + DockGeometry.crossPadding + DockGeometry.indicatorAreaDepth)
            return edge.isVertical
                ? min(availableDepth, contentHeight + DockGeometry.outerMargin + 260)
                : max(128, contentHeight + DockGeometry.outerMargin + 48)
        }
        /// Resting glass thickness. Magnification never changes it.
        var surfaceDepth: CGFloat {
            iconSize + DockGeometry.indicatorAreaDepth + 2 * DockGeometry.crossPadding
        }
        var viewportSize: CGSize { edge.size(length: viewportLength, depth: panelDepth) }
        var canvasSize: CGSize { edge.size(length: canvasLength, depth: panelDepth) }

        /// Visible length, capped to the available display area.
        let viewportLength: CGFloat
        /// Scrollable length, including the reserved magnification envelope.
        let canvasLength: CGFloat
        /// Stable canvas-space along-axis positions; never replace these with animated positions.
        let restingCenters: [CGFloat]
        /// Index of the first running-only item, or nil when one section is empty.
        let separatorIndex: Int?

        /// Computes icon dimensions from a canvas-space pointer along-axis coordinate.
        /// A nil pointer or Reduce Motion returns resting sizes.
        func sizes(pointerAlong: CGFloat?, reduceMotion: Bool) -> [CGFloat] {
            restingCenters.map { center in
                guard let pointerAlong, !reduceMotion else { return iconSize }
                // Measure against resting centers so moving icons do not chase the pointer.
                let distance = abs(pointerAlong - center)
                let radius = (iconSize + itemSpacing) * 2.5
                let influence = max(0, 1 - distance / radius)
                return iconSize * (1 + (magnification - 1) * influence * influence)
            }
        }

        /// Positions the supplied item sizes while preserving spacing and the section gap.
        /// - Parameter sizes: One size per item, in the layout’s original order.
        func centers(sizes: [CGFloat]) -> [CGFloat] {
            let width = contentLength(sizes: sizes)
            var x = (canvasLength - width) / 2 + DockGeometry.padding
            return sizes.enumerated().map { index, size in
                if index == separatorIndex { x += DockGeometry.separatorLength }
                let center = x + size / 2
                x += size + itemSpacing
                return center
            }
        }

        /// Glass bounds in top-left canvas coordinates. Hover affects length, never thickness.
        func surfaceFrame(sizes: [CGFloat]) -> CGRect {
            let width = contentLength(sizes: sizes)
            let height = surfaceDepth
            return edge.rect(CGRect(x: (canvasLength - width) / 2,
                          y: panelDepth - DockGeometry.outerMargin - height,
                          width: width, height: height), depth: panelDepth)
        }

        /// App-button bounds, including the running indicator, anchored to a fixed outer baseline.
        /// These bounds may extend inward beyond the glass while remaining inside the panel envelope.
        func buttonFrame(centerAlong: CGFloat, size: CGFloat) -> CGRect {
            let height = size + DockGeometry.indicatorAreaDepth
            return edge.rect(CGRect(x: centerAlong - size / 2,
                          y: panelDepth - DockGeometry.outerMargin - DockGeometry.crossPadding - height,
                          width: size, height: height), depth: panelDepth)
        }

        /// Bounds of the image square within its button, excluding the indicator row and any
        /// transparency supplied by the app's icon artwork. Shared by separators and drag gaps.
        func iconFrame(centerAlong: CGFloat, size: CGFloat) -> CGRect {
            edge.rect(CGRect(x: centerAlong - size / 2,
                y: panelDepth - DockGeometry.outerMargin - DockGeometry.crossPadding - size - DockGeometry.indicatorAreaDepth,
                width: size, height: size), depth: panelDepth)
        }

        /// Inward space for upright labels and feedback, in canvas coordinates.
        func calloutRegion(size: CGFloat, length: CGFloat) -> CGRect {
            let inner = panelDepth - DockGeometry.outerMargin - max(surfaceDepth,
                size + DockGeometry.indicatorAreaDepth + DockGeometry.crossPadding + 12)
            return edge.rect(CGRect(x: 0, y: 0, width: length, height: max(1, inner)), depth: panelDepth)
        }

        /// Length of the painted surface, including padding, spacing, and any section gap.
        func contentLength(sizes: [CGFloat]) -> CGFloat {
            max(64, sizes.reduce(0, +) + CGFloat(max(0, sizes.count - 1)) * itemSpacing
                + DockGeometry.padding * 2 + (separatorIndex == nil ? 0 : DockGeometry.separatorLength))
        }
    }

    /// Builds a resting layout, reducing icons to 32 points before allowing along-axis overflow.
    /// - Parameters:
    ///   - count: Total item count.
    ///   - favoriteCount: Number of leading pinned items, between zero and `count`.
    ///   - availableLength: Chosen reference frame length along the selected edge, in logical points.
    ///   - availableDepth: Reference frame dimension perpendicular to the selected edge.
    ///   - settings: Requested appearance; invalid values fall back to defaults.
    static func layout(count: Int, favoriteCount: Int, availableLength: CGFloat, availableDepth: CGFloat = 900, settings: DockSettings = .defaults) -> Layout {
        let settings = settings.normalized ?? .defaults
        let viewportLimit = max(64, availableLength - 16)
        let separator: Int? = favoriteCount > 0 && favoriteCount < count ? favoriteCount : nil
        let itemSpacing = CGFloat(settings.itemSpacing)
        let extra = padding * 2 + CGFloat(max(0, count - 1)) * itemSpacing
            + (separator == nil ? 0 : separatorLength)
        // Reserve the magnification envelope, rather than resizing the window on every mouse move.
        let size = min(CGFloat(settings.iconSize), max(32, (viewportLimit - extra) / CGFloat(max(1, count) + 2)))
        let restingWidth = max(64, CGFloat(count) * size + extra)
        // The quadratic falloff spans 2.5 resting spacings. Its summed influence is at most 1.8,
        // so two extra icon widths cover the supported maximum 2× scale, including the spring.
        let canvas = restingWidth + size * 2
        let viewport = min(viewportLimit, canvas)
        let initial = Layout(iconSize: size, magnification: CGFloat(settings.magnification), itemSpacing: itemSpacing, edge: settings.edge, availableDepth: max(64, availableDepth), viewportLength: viewport, canvasLength: canvas,
                             restingCenters: [], separatorIndex: separator)
        let centers = initial.centers(sizes: Array(repeating: size, count: count))
        return Layout(iconSize: size, magnification: CGFloat(settings.magnification), itemSpacing: itemSpacing, edge: settings.edge, availableDepth: max(64, availableDepth), viewportLength: viewport, canvasLength: canvas,
                      restingCenters: centers, separatorIndex: separator)
    }
}
