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
    /// Clear space between two glass islands, not including each island's own padding.
    /// The screenshot's sections are separate capsules, so this gap shows the desktop through.
    static let islandGap: CGFloat = 22

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
                                    + DockGeometry.crossPadding + DockGeometry.indicatorAreaDepth)
            return edge.isVertical
                ? min(availableDepth, contentHeight + DockGeometry.outerMargin + calloutReserve)
                : max(128, contentHeight + DockGeometry.outerMargin + calloutReserve)
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
        /// Entry indices that begin a new glass island. Index 0 is never included.
        ///
        /// The gap replaces the old hairline divider: each island draws its own material,
        /// and `islandGap` of desktop shows between them.
        let separatorIndices: Set<Int>
        /// Spoken names for the islands, in visual order. Empty when a caller only needed geometry.
        let islandTitles: [String]

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
                // The previous icon already added ordinary spacing. A boundary replaces that
                // spacing with this island's trailing padding, the open gap, and the next
                // island's leading padding.
                if separatorIndices.contains(index) {
                    x += DockGeometry.padding * 2 + DockGeometry.islandGap - itemSpacing
                }
                let center = x + size / 2
                x += size + itemSpacing
                return center
            }
        }

        /// Half-open tile ranges, one per glass island, in visual order.
        ///
        /// Index 0 begins the first island. Each later entry in `separatorIndices` begins the next.
        func islandRanges(count: Int) -> [Range<Int>] {
            guard count > 0 else { return [] }
            let boundaries = separatorIndices.filter { $0 > 0 && $0 < count }.sorted()
            var ranges: [Range<Int>] = []
            var start = 0
            for boundary in boundaries where boundary > start {
                ranges.append(start..<boundary)
                start = boundary
            }
            if start < count { ranges.append(start..<count) }
            return ranges
        }

        /// One glass capsule per island, in top-left canvas coordinates.
        /// Magnification changes length and never thickness. A single island matches `surfaceFrame`.
        func islandFrames(sizes: [CGFloat]) -> [CGRect] {
            let centers = centers(sizes: sizes)
            let count = min(sizes.count, centers.count)
            let height = surfaceDepth
            return islandRanges(count: count).map { range in
                let first = range.lowerBound
                let last = range.upperBound - 1
                let minAlong = centers[first] - sizes[first] / 2 - DockGeometry.padding
                let maxAlong = centers[last] + sizes[last] / 2 + DockGeometry.padding
                return edge.rect(CGRect(x: minAlong,
                                         y: panelDepth - DockGeometry.outerMargin - height,
                                         width: max(1, maxAlong - minAlong),
                                         height: height), depth: panelDepth)
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

        /// Length of every island, including each island's padding and the open gaps between them.
        func contentLength(sizes: [CGFloat]) -> CGFloat {
            let boundaries = separatorIndices.filter { $0 > 0 && $0 < sizes.count }.count
            let islands = sizes.isEmpty ? 0 : boundaries + 1
            let spacing = max(0, sizes.count - 1 - boundaries)
            let length = sizes.reduce(0, +) + CGFloat(spacing) * itemSpacing
                + CGFloat(boundaries) * DockGeometry.islandGap
                + CGFloat(islands) * DockGeometry.padding * 2
            return max(64, length)
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
    /// - Parameter islandStarts: Indices that begin a glass island. When present, these replace
    ///   the pinned and utility boundaries derived from the counts. Index 0 is implied.
    static func layout(count: Int, favoriteCount: Int, utilityCount: Int = 0, leadingUtilityCount: Int = 0, availableLength: CGFloat, availableDepth: CGFloat = 900, settings: DockSettings = .defaults, calloutReserve: CGFloat? = nil, islandStarts: [Int]? = nil, islandTitles: [String] = []) -> Layout {
        let settings = settings.normalized ?? .defaults
        let viewportLimit = max(64, availableLength - 16)
        let utilityCount = min(max(0, utilityCount), count)
        let leading = min(max(0, leadingUtilityCount), count - utilityCount)
        let appCount = count - utilityCount - leading
        var separators = Set<Int>()
        if let islandStarts {
            separators = Set(islandStarts.filter { $0 > 0 && $0 < count })
        } else {
            if favoriteCount > 0 && favoriteCount < appCount { separators.insert(leading + favoriteCount) }
            if utilityCount > 0 && appCount > 0 { separators.insert(leading + appCount) }
        }
        let itemSpacing = CGFloat(settings.itemSpacing)
        let boundaries = separators.filter { $0 > 0 && $0 < count }.count
        let islands = count == 0 ? 0 : boundaries + 1
        let spacing = max(0, count - 1 - boundaries)
        let extra = CGFloat(spacing) * itemSpacing + CGFloat(boundaries) * islandGap
            + CGFloat(islands) * padding * 2
        // Reserve the magnification envelope, rather than resizing the window on every mouse move.
        let size = min(CGFloat(settings.iconSize), max(32, (viewportLimit - extra) / CGFloat(max(1, count) + 2)))
        let restingWidth = max(64, CGFloat(count) * size + extra)
        // The quadratic falloff spans 2.5 resting spacings. Its summed influence is at most 1.8,
        // so two extra icon widths cover the supported maximum 2× scale, including the spring.
        let canvas = restingWidth + size * 2
        let viewport = min(viewportLimit, canvas)
        let reserve = calloutReserve ?? (settings.edge.isVertical ? 260 : 72)
        let initial = Layout(iconSize: size, magnification: CGFloat(settings.magnification), itemSpacing: itemSpacing, edge: settings.edge, availableDepth: max(64, availableDepth), calloutReserve: reserve, viewportLength: viewport, canvasLength: canvas,
                             restingCenters: [], separatorIndices: separators, islandTitles: islandTitles)
        let centers = initial.centers(sizes: Array(repeating: size, count: count))
        return Layout(iconSize: size, magnification: CGFloat(settings.magnification), itemSpacing: itemSpacing, edge: settings.edge, availableDepth: max(64, availableDepth), calloutReserve: reserve, viewportLength: viewport, canvasLength: canvas,
                      restingCenters: centers, separatorIndices: separators, islandTitles: islandTitles)
    }
}
