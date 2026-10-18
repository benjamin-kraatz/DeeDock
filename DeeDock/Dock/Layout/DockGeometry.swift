import Foundation
import CoreGraphics

/// All geometry uses logical points; screen frames may have negative origins.
enum DockGeometry {
    /// Along-axis inset from the glass edge to the first and last icon squares.
    static let padding: CGFloat = 6
    /// Inset on both sides of the icon and indicator across the glass thickness.
    static let crossPadding: CGFloat = 6
    /// Gap between the image square and its running indicator.
    static let indicatorSpacing: CGFloat = 0
    static let indicatorSize: CGFloat = 4
    /// Reserved even for apps that are not running, so their icons share the outer baseline.
    static var indicatorAreaDepth: CGFloat { indicatorSpacing + indicatorSize }
    /// Inset of the glass surface from the panel outer edge, in points.
    static let outerMargin: CGFloat = 8
    static let separatorLength: CGFloat = 16

    /// Island bands laid along the dock when DOKK Islands are on.
    ///
    /// `starts` are the slot indices that begin each island; the first is always 0. Between two
    /// islands the row shows `padding`, then `gap`, then `padding` instead of one item spacing, and
    /// the glass thickness uses `padding` across the dock as well.
    struct IslandLayout: Equatable {
        let starts: [Int]
        let gap: CGFloat
        let padding: CGFloat

        init(starts: [Int], gap: CGFloat, padding: CGFloat) {
            let sorted = Array(Set(starts.filter { $0 > 0 })).sorted()
            self.starts = [0] + sorted
            self.gap = max(0, gap)
            self.padding = max(0, padding)
        }

        /// Number of islands for `count` items. Starts past the end never open an island.
        func islandCount(for count: Int) -> Int {
            count == 0 ? 0 : starts.filter { $0 < count }.count
        }

        /// Along-axis length added by island edges and gaps, beyond items and item spacing.
        func extraLength(count: Int, itemSpacing: CGFloat) -> CGFloat {
            let islands = islandCount(for: count)
            guard islands > 0 else { return padding * 2 }
            return padding * 2 * CGFloat(islands) + gap * CGFloat(islands - 1) - itemSpacing * CGFloat(islands - 1)
        }
    }

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
        /// Inward space reserved for labels, errors, and the timeline glance card.
        let calloutReserve: CGFloat
        /// Stable envelope accommodates the largest icon, running indicator, and hover label.
        var panelDepth: CGFloat {
            // Horizontal docks keep 72 points for hover labels. Timeline browsing raises that so
            // the glance card stays inside the transparent panel instead of clipping at the top.
            let contentHeight = max(surfaceDepth, ceil(iconSize * magnification)
                                    + crossInset + DockGeometry.indicatorAreaDepth)
            return edge.isVertical
                ? min(availableDepth, contentHeight + DockGeometry.outerMargin + calloutReserve)
                : max(128, contentHeight + DockGeometry.outerMargin + calloutReserve)
        }
        /// Resting glass thickness. Magnification never changes it.
        var surfaceDepth: CGFloat {
            iconSize + DockGeometry.indicatorAreaDepth + 2 * crossInset
        }
        var viewportSize: CGSize { edge.size(length: viewportLength, depth: panelDepth) }
        var canvasSize: CGSize { edge.size(length: canvasLength, depth: panelDepth) }

        /// Visible length, capped to the available display area.
        let viewportLength: CGFloat
        /// Scrollable length, including the reserved magnification envelope.
        let canvasLength: CGFloat
        /// Stable canvas-space along-axis positions; never replace these with animated positions.
        let restingCenters: [CGFloat]
        /// Entry indices preceded by a divider, for app-section and trailing utility boundaries.
        /// Empty while islands are drawn, since island gaps replace dividers.
        let separatorIndices: Set<Int>
        /// Island bands, or nil for one continuous glass surface.
        var islands: IslandLayout? = nil

        /// Inset from the glass edge to the first and last icon squares along the dock.
        var alongInset: CGFloat { islands?.padding ?? DockGeometry.padding }
        /// Inset on both sides of the icon and indicator across the glass thickness.
        var crossInset: CGFloat { islands?.padding ?? DockGeometry.crossPadding }

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
            var x = (canvasLength - width) / 2 + alongInset
            return sizes.enumerated().map { index, size in
                if let islands, index > 0, islands.starts.contains(index) {
                    // The previous item already advanced by one item spacing; an island boundary
                    // replaces it with the closing edge, the gap, and the next island's opening edge.
                    x += islands.padding * 2 + islands.gap - itemSpacing
                } else if separatorIndices.contains(index) {
                    x += DockGeometry.separatorLength
                }
                let center = x + size / 2
                x += size + itemSpacing
                return center
            }
        }

        /// Glass bounds in top-left canvas coordinates. Hover affects length, never thickness.
        /// With islands this is the union of every island, for hit testing and visibility.
        func surfaceFrame(sizes: [CGFloat]) -> CGRect {
            let width = contentLength(sizes: sizes)
            let height = surfaceDepth
            return edge.rect(CGRect(x: (canvasLength - width) / 2,
                          y: panelDepth - DockGeometry.outerMargin - height,
                          width: width, height: height), depth: panelDepth)
        }

        /// One glass rect per island, in top-left canvas coordinates and island order. Without
        /// islands this is the single surface. Empty for an empty dock.
        func islandFrames(sizes: [CGFloat]) -> [CGRect] {
            guard let islands, !sizes.isEmpty else { return sizes.isEmpty && islands != nil ? [] : [surfaceFrame(sizes: sizes)] }
            let centers = centers(sizes: sizes)
            let starts = islands.starts.filter { $0 < sizes.count }
            let height = surfaceDepth
            let y = panelDepth - DockGeometry.outerMargin - height
            return starts.indices.map { island in
                let first = starts[island]
                let last = island + 1 < starts.count ? starts[island + 1] - 1 : sizes.count - 1
                let leading = centers[first] - sizes[first] / 2 - islands.padding
                let trailing = centers[last] + sizes[last] / 2 + islands.padding
                return edge.rect(CGRect(x: leading, y: y, width: trailing - leading, height: height), depth: panelDepth)
            }
        }

        /// App-button bounds, including the running indicator, anchored to a fixed outer baseline.
        /// These bounds may extend inward beyond the glass while remaining inside the panel envelope.
        func buttonFrame(centerAlong: CGFloat, size: CGFloat) -> CGRect {
            let height = size + DockGeometry.indicatorAreaDepth
            return edge.rect(CGRect(x: centerAlong - size / 2,
                          y: panelDepth - DockGeometry.outerMargin - crossInset - height,
                          width: size, height: height), depth: panelDepth)
        }

        /// Bounds of the image square within its button, excluding the indicator row and any
        /// transparency supplied by the app's icon artwork. Shared by separators and drag gaps.
        func iconFrame(centerAlong: CGFloat, size: CGFloat) -> CGRect {
            edge.rect(CGRect(x: centerAlong - size / 2,
                y: panelDepth - DockGeometry.outerMargin - crossInset - size - DockGeometry.indicatorAreaDepth,
                width: size, height: size), depth: panelDepth)
        }

        /// Inward space for upright labels and feedback, in canvas coordinates.
        func calloutRegion(size: CGFloat, length: CGFloat) -> CGRect {
            let inner = panelDepth - DockGeometry.outerMargin - max(surfaceDepth,
                size + DockGeometry.indicatorAreaDepth + crossInset + 12)
            return edge.rect(CGRect(x: 0, y: 0, width: length, height: max(1, inner)), depth: panelDepth)
        }

        /// Length of the painted surface, including padding, spacing, and any section gap.
        func contentLength(sizes: [CGFloat]) -> CGFloat {
            let items = sizes.reduce(0, +) + CGFloat(max(0, sizes.count - 1)) * itemSpacing
            if let islands {
                return max(64, items + islands.extraLength(count: sizes.count, itemSpacing: itemSpacing))
            }
            return max(64, items + DockGeometry.padding * 2 + CGFloat(separatorIndices.count) * DockGeometry.separatorLength)
        }
    }

    /// Builds a resting layout, reducing icons to 32 points before allowing along-axis overflow.
    /// - Parameters:
    ///   - count: Total item count.
    ///   - favoriteCount: Number of leading pinned items, between zero and `count`.
    ///   - utilityCount: Number of trailing utility items separated from application sections.
    ///   - availableLength: Chosen reference frame length along the selected edge, in logical points.
    ///   - availableDepth: Reference frame dimension perpendicular to the selected edge.
    ///   - settings: Requested appearance; invalid values fall back to defaults.
    ///   - calloutReserve: Override the inward label band. Timeline browsing passes a taller
    ///     reserve so the glance card is not clipped by the panel envelope.
    ///   - islands: Island bands to lay out instead of dividers. Nil draws one continuous surface.
    static func layout(count: Int, favoriteCount: Int, utilityCount: Int = 0, leadingUtilityCount: Int = 0, availableLength: CGFloat, availableDepth: CGFloat = 900, settings: DockSettings = .defaults, calloutReserve: CGFloat? = nil, islands: IslandLayout? = nil) -> Layout {
        let settings = settings.normalized ?? .defaults
        let viewportLimit = max(64, availableLength - 16)
        let utilityCount = min(max(0, utilityCount), count)
        let leading = min(max(0, leadingUtilityCount), count - utilityCount)
        let appCount = count - utilityCount - leading
        var separators = Set<Int>()
        if islands == nil {
            if favoriteCount > 0 && favoriteCount < appCount { separators.insert(leading + favoriteCount) }
            if utilityCount > 0 && appCount > 0 { separators.insert(leading + appCount) }
        }
        let itemSpacing = CGFloat(settings.itemSpacing)
        let extra = CGFloat(max(0, count - 1)) * itemSpacing
            + (islands?.extraLength(count: count, itemSpacing: itemSpacing)
               ?? padding * 2 + CGFloat(separators.count) * separatorLength)
        // Reserve the magnification envelope, rather than resizing the window on every mouse move.
        let size = min(CGFloat(settings.iconSize), max(32, (viewportLimit - extra) / CGFloat(max(1, count) + 2)))
        let restingWidth = max(64, CGFloat(count) * size + extra)
        // The quadratic falloff spans 2.5 resting spacings. Its summed influence is at most 1.8,
        // so two extra icon widths cover the supported maximum 2× scale, including the spring.
        let canvas = restingWidth + size * 2
        let viewport = min(viewportLimit, canvas)
        let reserve = calloutReserve ?? (settings.edge.isVertical ? 260 : 72)
        let initial = Layout(iconSize: size, magnification: CGFloat(settings.magnification), itemSpacing: itemSpacing, edge: settings.edge, availableDepth: max(64, availableDepth), calloutReserve: reserve, viewportLength: viewport, canvasLength: canvas,
                             restingCenters: [], separatorIndices: separators, islands: islands)
        let centers = initial.centers(sizes: Array(repeating: size, count: count))
        return Layout(iconSize: size, magnification: CGFloat(settings.magnification), itemSpacing: itemSpacing, edge: settings.edge, availableDepth: max(64, availableDepth), calloutReserve: reserve, viewportLength: viewport, canvasLength: canvas,
                      restingCenters: centers, separatorIndices: separators, islands: islands)
    }
}
