import CoreGraphics
import SwiftUI

/// Sizes for marks on a picture of a given pixel size.
///
/// Everything is derived from one unit so a pen line on a 4K capture and on a small utility window
/// look the same relative to the picture. Values are document pixels; the canvas multiplies by its
/// display scale and the export renders at scale 1.
nonisolated struct WindowMarkupMetrics: Equatable, Sendable {
    let unit: CGFloat

    init(documentSize: CGSize) {
        unit = max(2, min(documentSize.width, documentSize.height) / 360)
    }

    func penWidth(_ weight: WindowMarkupWeight) -> CGFloat { 1.6 * unit * weight.multiplier }
    func highlightWidth(_ weight: WindowMarkupWeight) -> CGFloat { 5.5 * unit * weight.multiplier }
    func arrowWidth(_ weight: WindowMarkupWeight) -> CGFloat { 1.7 * unit * weight.multiplier }
    func arrowHead(_ weight: WindowMarkupWeight) -> CGFloat { 5.5 * unit * weight.multiplier }
    func rectangleWidth(_ weight: WindowMarkupWeight) -> CGFloat { 1.5 * unit * weight.multiplier }
    var rectangleRadius: CGFloat { 1.4 * unit }
    func textSize(_ weight: WindowMarkupWeight) -> CGFloat { 7 * unit * weight.multiplier }
    func badgeRadius(_ weight: WindowMarkupWeight) -> CGFloat { 5.5 * unit * weight.multiplier }
    /// Half the distance a hit test tolerates around a thin mark.
    var hitSlop: CGFloat { 4 * unit }
    /// Pixel block for redaction; coarse enough to defeat zooming, fine enough to keep layout readable.
    var pixelBlock: Int { Int(max(8, (unit * 4).rounded())) }
}

/// Pure geometry for marks: outlines, bounds, and hit testing in document pixels.
nonisolated enum WindowMarkupGeometry {
    /// A smoothed pen or highlighter outline. Quadratic midpoints turn the sampled points into a
    /// curve, so fast strokes do not show polygon corners; a single point becomes a dot.
    static func strokePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else {
            path.addLine(to: CGPoint(x: first.x + 0.01, y: first.y))
            return path
        }
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        for index in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[index].x + points[index + 1].x) / 2,
                              y: (points[index].y + points[index + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[index])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    /// The arrow's shaft; the head is a separate filled path so both scale independently.
    static func arrowShaft(from: CGPoint, to: CGPoint, head: CGFloat) -> Path {
        var path = Path()
        let length = hypot(to.x - from.x, to.y - from.y)
        guard length > 0.5 else { return path }
        // Stop the shaft a little short so its round cap does not poke through the head's tip.
        let inset = min(length, head * 0.8)
        let end = CGPoint(x: to.x - (to.x - from.x) / length * inset, y: to.y - (to.y - from.y) / length * inset)
        path.move(to: from)
        path.addLine(to: end)
        return path
    }

    static func arrowHead(from: CGPoint, to: CGPoint, head: CGFloat) -> Path {
        var path = Path()
        let length = hypot(to.x - from.x, to.y - from.y)
        guard length > 0.5 else { return path }
        let angle = atan2(to.y - from.y, to.x - from.x)
        let spread: CGFloat = .pi / 7
        let left = CGPoint(x: to.x - head * cos(angle - spread), y: to.y - head * sin(angle - spread))
        let right = CGPoint(x: to.x - head * cos(angle + spread), y: to.y - head * sin(angle + spread))
        path.move(to: to)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }

    /// The rectangle two drag points describe, normalised so either corner may be first.
    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// The area a mark occupies, including its stroke, used for selection outlines and hit testing.
    static func bounds(of element: WindowMarkupElement, metrics: WindowMarkupMetrics) -> CGRect {
        let weight = element.weight
        switch element.shape {
        case .stroke(let points):
            return points.bounds.insetBy(dx: -metrics.penWidth(weight), dy: -metrics.penWidth(weight))
        case .highlight(let points):
            return points.bounds.insetBy(dx: -metrics.highlightWidth(weight) / 2,
                                         dy: -metrics.highlightWidth(weight) / 2)
        case .arrow(let from, let to):
            return [from, to].bounds.insetBy(dx: -metrics.arrowHead(weight), dy: -metrics.arrowHead(weight))
        case .rectangle(let rect):
            return rect.insetBy(dx: -metrics.rectangleWidth(weight), dy: -metrics.rectangleWidth(weight))
        case .text(let string, let origin):
            // An estimate: the canvas measures real glyphs, but selection needs no more than this.
            let size = metrics.textSize(weight)
            let lines = max(1, string.split(separator: "\n", omittingEmptySubsequences: false).count)
            let longest = string.split(separator: "\n", omittingEmptySubsequences: false).map(\.count).max() ?? 0
            return CGRect(x: origin.x, y: origin.y,
                          width: max(size, CGFloat(longest) * size * 0.58), height: CGFloat(lines) * size * 1.25)
        case .badge(_, let center):
            let radius = metrics.badgeRadius(weight)
            return CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
        case .redact(let rect, _):
            return rect
        }
    }

    /// The topmost mark under `point`, if any. Thin marks are tested against their outline with
    /// some slop; filled and boxed marks against their area.
    static func hit(_ point: CGPoint, in elements: [WindowMarkupElement], metrics: WindowMarkupMetrics) -> UUID? {
        for element in elements.reversed() {
            let bounds = bounds(of: element, metrics: metrics).insetBy(dx: -metrics.hitSlop, dy: -metrics.hitSlop)
            guard bounds.contains(point) else { continue }
            switch element.shape {
            case .stroke(let points), .highlight(let points):
                let width = element.shape.isHighlight ? metrics.highlightWidth(element.weight)
                                                      : metrics.penWidth(element.weight)
                if distance(from: point, toPolyline: points) <= width / 2 + metrics.hitSlop { return element.id }
            case .arrow(let from, let to):
                if distance(from: point, toPolyline: [from, to]) <= metrics.arrowHead(element.weight) { return element.id }
            case .rectangle(let rect):
                // A box is grabbed by its edge, so the window content inside stays selectable.
                let tolerance = metrics.rectangleWidth(element.weight) + metrics.hitSlop
                if rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point),
                   !rect.insetBy(dx: tolerance, dy: tolerance).contains(point) { return element.id }
            case .text, .badge, .redact:
                return element.id
            }
        }
        return nil
    }

    /// Shortest distance from `point` to the segments joining `points` in order.
    static func distance(from point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        guard let first = points.first else { return .infinity }
        guard points.count > 1 else { return hypot(point.x - first.x, point.y - first.y) }
        var best = CGFloat.infinity
        for index in 0..<(points.count - 1) {
            best = min(best, distance(from: point, toSegment: points[index], points[index + 1]))
        }
        return best
    }

    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }

    /// Clamps a crop to the document and refuses slivers that would export nothing useful.
    static func clampedCrop(_ rect: CGRect, in size: CGSize) -> CGRect? {
        let bounded = rect.intersection(CGRect(origin: .zero, size: size)).integral
        guard !bounded.isNull, bounded.width >= 8, bounded.height >= 8 else { return nil }
        return bounded
    }
}

nonisolated extension WindowMarkupShape {
    var isHighlight: Bool {
        if case .highlight = self { return true }
        return false
    }
}

nonisolated private extension Array where Element == CGPoint {
    var bounds: CGRect {
        guard let first else { return .null }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in dropFirst() {
            minX = Swift.min(minX, point.x); minY = Swift.min(minY, point.y)
            maxX = Swift.max(maxX, point.x); maxY = Swift.max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Places the markup window and the picture inside it.
///
/// Screen inputs are AppKit points, y up. The picture keeps the capture's aspect ratio; the window
/// wraps it in fixed chrome and never exceeds the display's usable area.
nonisolated enum WindowMarkupLayout {
    /// Space above the picture for the title bar and header.
    static let headerHeight: CGFloat = 56
    /// Space below the picture for the action bar.
    static let footerHeight: CGFloat = 74
    /// Horizontal room for the tool palette on the leading side and symmetrical breathing room.
    static let sideInset: CGFloat = 76
    static let minimumSize = CGSize(width: 680, height: 460)
    /// Largest share of the display's usable area the window takes when it opens.
    static let openingShare: CGFloat = 0.86

    /// The window frame for a picture of `documentSize` pixels shown on `visibleFrame`, centred.
    static func panelFrame(documentSize: CGSize, visibleFrame: CGRect) -> CGRect {
        let limit = CGSize(width: max(minimumSize.width, visibleFrame.width * openingShare),
                           height: max(minimumSize.height, visibleFrame.height * openingShare))
        let pictureLimit = CGSize(width: limit.width - 2 * sideInset, height: limit.height - headerHeight - footerHeight)
        let aspect = max(0.1, documentSize.width / max(1, documentSize.height))
        var picture = CGSize(width: pictureLimit.width, height: pictureLimit.width / aspect)
        if picture.height > pictureLimit.height {
            picture = CGSize(width: pictureLimit.height * aspect, height: pictureLimit.height)
        }
        let size = CGSize(width: min(limit.width, max(minimumSize.width, picture.width + 2 * sideInset)),
                          height: min(limit.height, max(minimumSize.height, picture.height + headerHeight + footerHeight)))
        return CGRect(x: (visibleFrame.midX - size.width / 2).rounded(), y: (visibleFrame.midY - size.height / 2).rounded(),
                      width: size.width.rounded(), height: size.height.rounded())
    }

    /// Where the picture sits inside a stage area, aspect-fitted and centred; scale is points per pixel.
    static func pictureFrame(documentSize: CGSize, stage: CGSize) -> (frame: CGRect, scale: CGFloat) {
        guard documentSize.width > 0, documentSize.height > 0, stage.width > 0, stage.height > 0 else {
            return (.zero, 1)
        }
        let scale = min(stage.width / documentSize.width, stage.height / documentSize.height)
        let size = CGSize(width: documentSize.width * scale, height: documentSize.height * scale)
        return (CGRect(x: (stage.width - size.width) / 2, y: (stage.height - size.height) / 2,
                       width: size.width, height: size.height), scale)
    }

    /// Padding around the picture when the presentation frame is on, in document pixels.
    static func framePadding(documentSize: CGSize) -> CGFloat {
        (min(documentSize.width, documentSize.height) * 0.08).rounded()
    }
}
