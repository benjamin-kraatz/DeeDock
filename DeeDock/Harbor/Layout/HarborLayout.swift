import CoreGraphics
import Foundation

/// One app group as the layout sees it: shapes and measured widths, no views.
nonisolated struct HarborLayoutGroup: Equatable, Sendable {
    /// One visible window: its identity and width-to-height ratio.
    nonisolated struct Window: Equatable, Sendable {
        let id: UUID
        let aspect: CGFloat
    }

    /// One minimized or hidden window's chip and its measured width in points.
    nonisolated struct Chip: Equatable, Sendable {
        let id: UUID
        let width: CGFloat
    }

    let id: String
    /// Visible windows, front to back.
    let windows: [Window]
    let chips: [Chip]
    /// Width of the icon, app name, and window count header, in points.
    let headerWidth: CGFloat
    /// Draws this group alone in the first row, with larger thumbnails.
    var isFront = false
}

/// Where every group, thumbnail, caption, and chip goes, in the bounds' coordinate space.
nonisolated struct HarborLayoutResult: Equatable, Sendable {
    var groups: [String: CGRect] = [:]
    var windows: [UUID: CGRect] = [:]
    var captions: [UUID: CGRect] = [:]
    var chips: [UUID: CGRect] = [:]
    /// Shared thumbnail height for ordinary groups.
    var thumbnailHeight: CGFloat = 0
    /// Thumbnail height of the front app's group, when one leads the layout.
    var frontThumbnailHeight: CGFloat?
    /// Whether captions under thumbnails have room for a second line.
    var tallCaptions = false
    /// True when even the smallest thumbnails do not fit; the content then runs past `bounds`.
    var overflows = false
    /// The height everything occupies, which is more than the bounds when `overflows` is true.
    var contentHeight: CGFloat = 0
}

/// Packs app groups into rows with one shared thumbnail height.
///
/// Every ordinary group uses the same thumbnail height `H`, so windows read as one family; the
/// front app's group, when marked, takes a row of its own at `H × frontScale`. Groups fill rows
/// greedily in their given order, so the most recently used apps stay at the top. A binary
/// search finds the largest `H` for which all rows fit `bounds`. Within a group, windows wrap
/// into one to three rows depending on how many there are, and each row is centered.
///
/// The function is pure: callers measure text and supply widths, so tests can check placement
/// without AppKit.
nonisolated enum HarborLayout {
    nonisolated struct Metrics: Equatable, Sendable {
        var groupGap: CGFloat = 24
        var padding: CGFloat = 16
        var header: CGFloat = 46
        var windowGap: CGFloat = 18
        var rowGap: CGFloat = 8
        var chipHeight: CGFloat = 28
        var chipGap: CGFloat = 8
        var chipTopGap: CGFloat = 12
        var minimumThumbnail: CGFloat = 52
        var maximumThumbnail: CGFloat = 232
        /// "Front app large": the front group's thumbnails are this much taller.
        var frontScale: CGFloat = 1.6
        var maximumFrontThumbnail: CGFloat = 300
        /// Thumbnails at least this tall get a two-line caption.
        var tallCaptionThreshold: CGFloat = 104
        var tallCaption: CGFloat = 40
        var shortCaption: CGFloat = 22
        var captionGap: CGFloat = 5

        static let standard = Metrics()
    }

    static func place(_ groups: [HarborLayoutGroup], in bounds: CGRect,
                      metrics: Metrics = .standard) -> HarborLayoutResult {
        guard !groups.isEmpty, bounds.width > 0, bounds.height > 0 else { return HarborLayoutResult() }
        var low = metrics.minimumThumbnail, high = metrics.maximumThumbnail
        var best: Packing?
        // Twenty halvings narrow the height to well under a point.
        for _ in 0..<20 {
            let middle = (low + high) / 2
            if let packing = pack(groups, height: middle, bounds: bounds, metrics: metrics, force: false) {
                best = packing
                low = middle
            } else {
                high = middle
            }
        }
        let overflows = best == nil
        let packing = best ?? pack(groups, height: metrics.minimumThumbnail, bounds: bounds, metrics: metrics, force: true)!
        return place(packing, in: bounds, overflows: overflows, metrics: metrics)
    }

    /// Rows of measured groups for one thumbnail height.
    private nonisolated struct Packing {
        var rows: [[Measured]]
        var height: CGFloat
        var thumbnail: CGFloat
        var frontThumbnail: CGFloat?
    }

    private nonisolated struct Measured {
        let group: HarborLayoutGroup
        let thumbnail: CGFloat
        let caption: CGFloat
        /// Visible windows split into rows.
        let rows: [[HarborLayoutGroup.Window]]
        let rowWidths: [CGFloat]
        let bodyHeight: CGFloat
        let chipsWidth: CGFloat
        let size: CGSize
    }

    private static func pack(_ groups: [HarborLayoutGroup], height: CGFloat, bounds: CGRect,
                             metrics: Metrics, force: Bool) -> Packing? {
        var rows: [[Measured]] = []
        var current: [Measured] = []
        var currentWidth: CGFloat = 0
        var frontThumbnail: CGFloat?
        for group in groups {
            let thumbnail = group.isFront ? min(height * metrics.frontScale, metrics.maximumFrontThumbnail) : height
            if group.isFront { frontThumbnail = thumbnail }
            let measured = measure(group, thumbnail: thumbnail, metrics: metrics)
            if measured.size.width > bounds.width && !force { return nil }
            if group.isFront {
                if !current.isEmpty { rows.append(current); current = []; currentWidth = 0 }
                rows.append([measured])
                continue
            }
            if !current.isEmpty, currentWidth + metrics.groupGap + measured.size.width > bounds.width {
                rows.append(current)
                current = []
                currentWidth = 0
            }
            currentWidth += (current.isEmpty ? 0 : metrics.groupGap) + measured.size.width
            current.append(measured)
        }
        if !current.isEmpty { rows.append(current) }
        let total = rows.reduce(0) { $0 + ($1.map(\.size.height).max() ?? 0) }
            + metrics.groupGap * CGFloat(max(0, rows.count - 1))
        if total > bounds.height && !force { return nil }
        return Packing(rows: rows, height: total, thumbnail: height, frontThumbnail: frontThumbnail)
    }

    private static func measure(_ group: HarborLayoutGroup, thumbnail: CGFloat, metrics: Metrics) -> Measured {
        let count = group.windows.count
        let rowCount = count == 0 ? 0 : min(count, rowsFor(count, front: group.isFront))
        let perRow = rowCount == 0 ? 0 : Int((Double(count) / Double(rowCount)).rounded(.up))
        var rows: [[HarborLayoutGroup.Window]] = []
        if perRow > 0 {
            for start in stride(from: 0, to: count, by: perRow) {
                rows.append(Array(group.windows[start..<min(start + perRow, count)]))
            }
        }
        let rowWidths = rows.map { row in
            row.reduce(0) { $0 + max(0.2, $1.aspect) * thumbnail } + metrics.windowGap * CGFloat(row.count - 1)
        }
        let caption = thumbnail >= metrics.tallCaptionThreshold ? metrics.tallCaption : metrics.shortCaption
        let bodyHeight = rows.isEmpty ? 0
            : CGFloat(rows.count) * (thumbnail + metrics.captionGap + caption) + CGFloat(rows.count - 1) * metrics.rowGap
        let chipsWidth = group.chips.reduce(0) { $0 + $1.width } + metrics.chipGap * CGFloat(max(0, group.chips.count - 1))
        let inner = max(group.headerWidth, chipsWidth, rowWidths.max() ?? 0)
        let chipsHeight = group.chips.isEmpty ? 0 : (rows.isEmpty ? 0 : metrics.chipTopGap) + metrics.chipHeight
        let size = CGSize(width: inner + 2 * metrics.padding,
                          height: metrics.header + bodyHeight + chipsHeight + metrics.padding)
        return Measured(group: group, thumbnail: thumbnail, caption: caption, rows: rows, rowWidths: rowWidths,
                        bodyHeight: bodyHeight, chipsWidth: chipsWidth, size: size)
    }

    /// Windows wrap into more rows as a group grows, keeping groups closer to the display's shape.
    private static func rowsFor(_ count: Int, front: Bool) -> Int {
        if front { return count <= 4 ? 1 : count <= 8 ? 2 : 3 }
        return count <= 3 ? 1 : count <= 6 ? 2 : 3
    }

    private static func place(_ packing: Packing, in bounds: CGRect, overflows: Bool,
                              metrics: Metrics) -> HarborLayoutResult {
        var result = HarborLayoutResult()
        result.thumbnailHeight = packing.thumbnail
        result.frontThumbnailHeight = packing.frontThumbnail
        result.tallCaptions = packing.thumbnail >= metrics.tallCaptionThreshold
        result.overflows = overflows
        result.contentHeight = packing.height
        var y = bounds.minY + max(0, (bounds.height - packing.height) / 2)
        for row in packing.rows {
            let rowHeight = row.map(\.size.height).max() ?? 0
            let rowWidth = row.reduce(0) { $0 + $1.size.width } + metrics.groupGap * CGFloat(row.count - 1)
            var x = bounds.minX + (bounds.width - rowWidth) / 2
            for measured in row {
                let card = CGRect(x: x, y: y, width: measured.size.width, height: rowHeight)
                result.groups[measured.group.id] = card
                // Group contents sit below the header, centered in whatever height the row adds.
                let block = measured.size.height - metrics.header - metrics.padding
                let top = y + metrics.header + (rowHeight - metrics.header - metrics.padding - block) / 2
                for (index, windows) in measured.rows.enumerated() {
                    var windowX = x + (measured.size.width - measured.rowWidths[index]) / 2
                    let windowY = top + CGFloat(index) * (measured.thumbnail + metrics.captionGap + measured.caption + metrics.rowGap)
                    for window in windows {
                        let width = max(0.2, window.aspect) * measured.thumbnail
                        result.windows[window.id] = CGRect(x: windowX, y: windowY, width: width, height: measured.thumbnail)
                        result.captions[window.id] = CGRect(x: windowX - 6, y: windowY + measured.thumbnail + metrics.captionGap,
                                                            width: width + 12, height: measured.caption)
                        windowX += width + metrics.windowGap
                    }
                }
                var chipX = x + (measured.size.width - measured.chipsWidth) / 2
                let chipY = top + measured.bodyHeight + (measured.rows.isEmpty ? 0 : metrics.chipTopGap)
                for chip in measured.group.chips {
                    result.chips[chip.id] = CGRect(x: chipX, y: chipY, width: chip.width, height: metrics.chipHeight)
                    chipX += chip.width + metrics.chipGap
                }
                x += measured.size.width + metrics.groupGap
            }
            y += rowHeight + metrics.groupGap
        }
        return result
    }
}
