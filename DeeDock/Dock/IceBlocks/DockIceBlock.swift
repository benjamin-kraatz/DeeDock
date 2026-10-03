import SwiftUI

/// What a run of dock items is, which decides the colour of its ice block.
enum DockIceBlockRole: Equatable {
    case launcher, drives, pinned, running, utility

    /// Emitted-light colour of the block's rim, glow, and running markers.
    var tint: Color {
        switch self {
        case .launcher: Color(red: 0.56, green: 0.38, blue: 1.0)
        case .drives: Color(red: 0.16, green: 0.52, blue: 1.0)
        case .pinned: Color(red: 0.96, green: 0.76, blue: 0.46)
        case .running: Color(red: 0.24, green: 0.84, blue: 0.86)
        case .utility: Color(red: 0.70, green: 0.76, blue: 0.90)
        }
    }
}

/// How much roomier an ice block is than the standard glass. The along-axis values feed the
/// layout, so icons really move apart; the cross-axis values only enlarge the painted block,
/// which keeps the panel envelope, icon baseline, and hit regions identical to glass.
enum DockIceMetrics {
    /// Along-axis inset from a block's edge to its first and last icon squares.
    static let alongPadding: CGFloat = 14
    /// Room between the last icon of one block and the first of the next, on top of the item
    /// spacing: two paddings plus the visible gap.
    static let separatorLength: CGFloat = alongPadding * 2 + 6
    /// Extra painted thickness toward the desktop.
    static let inwardExtra: CGFloat = 8
    /// Extra painted thickness toward the screen edge. Must stay inside `DockGeometry.outerMargin`.
    static let outwardExtra: CGFloat = 4
    /// Distance the running marker drops into the extra outward room.
    static let indicatorDrop: CGFloat = 3
}

/// One contiguous run of dock items enclosed by a single block.
struct DockIceBlock: Identifiable, Equatable {
    /// Item indices in layout order.
    let range: Range<Int>
    let role: DockIceBlockRole
    var id: Int { range.lowerBound }

    /// Splits `roles` at the layout's separators. Blocks follow the layout rather than the
    /// roles, because only a separator reserves the gap two neighbouring blocks need.
    static func blocks(roles: [DockIceBlockRole], separators: Set<Int>) -> [DockIceBlock] {
        guard !roles.isEmpty else { return [] }
        var result: [DockIceBlock] = []
        var start = 0
        for index in 1...roles.count where index == roles.count || separators.contains(index) {
            result.append(DockIceBlock(range: start..<index, role: roles[start]))
            start = index
        }
        return result
    }

    /// Blocks for inert samples that have no real items: one colour per section, in dock order.
    static func sampleBlocks(count: Int, separators: Set<Int>) -> [DockIceBlock] {
        let palette: [DockIceBlockRole] = [.pinned, .running, .utility, .drives, .launcher]
        return blocks(roles: Array(repeating: .pinned, count: count), separators: separators)
            .enumerated().map { DockIceBlock(range: $1.range, role: palette[$0 % palette.count]) }
    }

    /// Separator indices that put every change of role in its own block, or `nil` when the
    /// style keeps the standard section dividers.
    static func separators(for slots: [DockRenderSlot], style: DockSurfaceStyle) -> Set<Int>? {
        guard style == .iceBlocks else { return nil }
        let roles = slots.map(\.iceRole)
        return Set(roles.indices.dropFirst().filter { roles[$0] != roles[$0 - 1] })
    }

    /// One tint per item index, for markers drawn by the items themselves.
    static func tints(_ blocks: [DockIceBlock]) -> [Color] {
        blocks.flatMap { Array(repeating: $0.role.tint, count: $0.range.count) }
    }
}

extension DockRenderSlot {
    var iceRole: DockIceBlockRole {
        switch self {
        case .launcher: .launcher
        case .volume: .drives
        case .app(let item): item.isFavorite ? .pinned : .running
        case .folder(let item): item.isDownloads ? .utility : .pinned
        case .group(let control): control.group == .pinned ? .pinned : .running
        case .gap: isPinned ? .pinned : .utility
        case .melt, .focus, .action, .sessionCapsule, .sessionCapsules, .shelf, .trash: .utility
        }
    }
}

extension DockGeometry.Layout {
    /// Block bounds in canvas coordinates: the surface's thickness plus the ice margins, and
    /// the block's own items plus the layout's end padding along the edge. Returns `nil` while
    /// the slots and the layout briefly disagree about the item count.
    func iceBlockFrame(_ range: Range<Int>, centers: [CGFloat], sizes: [CGFloat]) -> CGRect? {
        guard let first = range.first, let last = range.last, last < centers.count, last < sizes.count else { return nil }
        let start = centers[first] - sizes[first] / 2 - endPadding
        let end = centers[last] + sizes[last] / 2 + endPadding
        return iceFrame(start: start, end: end)
    }

    /// The whole dock as one block, for an empty dock.
    func iceFrame(surface sizes: [CGFloat]) -> CGRect {
        let length = contentLength(sizes: sizes)
        return iceFrame(start: (canvasLength - length) / 2, end: (canvasLength + length) / 2)
    }

    private func iceFrame(start: CGFloat, end: CGFloat) -> CGRect {
        let depth = surfaceDepth + DockIceMetrics.inwardExtra + DockIceMetrics.outwardExtra
        return edge.rect(CGRect(x: start, y: panelDepth - DockGeometry.outerMargin + DockIceMetrics.outwardExtra - depth,
                                width: end - start, height: depth), depth: panelDepth)
    }
}
