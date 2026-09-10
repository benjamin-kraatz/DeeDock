import CoreGraphics
import Foundation

/// One faint alignment guide in AppKit screen coordinates.
///
/// Vertical guides sit at an `x` (`position`) and span `y` from `start` to `end`.
/// Horizontal guides sit at a `y` and span `x`. `start` and `end` are not ordered.
nonisolated struct DockMagneticGuide: Equatable, Identifiable, Sendable {
    enum Axis: Equatable, Sendable {
        case vertical
        case horizontal
    }

    enum Kind: Equatable, Sendable {
        case edge
        case peer
    }

    var axis: Axis
    var position: CGFloat
    var start: CGFloat
    var end: CGFloat
    var kind: Kind

    var id: String { "\(axis)-\(kind)-\(position)-\(start)-\(end)" }

    /// Converts this guide into a top-left canvas whose AppKit origin is `canvas.origin`.
    func convertedToTopLeft(in canvas: CGRect) -> Self {
        let top = canvas.maxY
        switch axis {
        case .vertical:
            return DockMagneticGuide(
                axis: .vertical,
                position: position - canvas.minX,
                start: top - max(start, end),
                end: top - min(start, end),
                kind: kind
            )
        case .horizontal:
            return DockMagneticGuide(
                axis: .horizontal,
                position: top - position,
                start: min(start, end) - canvas.minX,
                end: max(start, end) - canvas.minX,
                kind: kind
            )
        }
    }
}

/// Snapped frame plus the guides that explain the snap. Empty guides mean a free drag.
nonisolated struct DockMagneticSnap: Equatable, Sendable {
    var frame: CGRect
    var guides: [DockMagneticGuide]

    var isMagnetized: Bool { !guides.isEmpty }

    static func free(_ frame: CGRect) -> Self { Self(frame: frame, guides: []) }
}

/// Edge and peer magnetism for a dragged pin or folder stack.
///
/// Each axis snaps independently. The closest alignment within `threshold` wins; coincident
/// targets share the same delta and all emit guides. There is no hysteresis: crossing the
/// threshold releases immediately so a disabled or Option-held drag never feels sticky.
enum DockMagnetism {
    /// Capture distance in points. Wide enough to feel magnetic, narrow enough to miss by intent.
    static let threshold: CGFloat = 12

    /// Aligns `frame` to screen edges and peer edges or centers when `enabled`.
    ///
    /// - Parameters:
    ///   - frame: Dragged pin or stack in AppKit screen coordinates.
    ///   - screens: Physical display frames; only the four edges are magnetic.
    ///   - peers: Other pin and stack frames. Edges and centers attract.
    ///   - threshold: Capture distance in points.
    ///   - enabled: When false, returns `frame` unchanged with no guides.
    /// - Returns: The snapped frame and the guides that explain any capture.
    static func snap(
        frame: CGRect,
        screens: [CGRect],
        peers: [CGRect],
        threshold: CGFloat = threshold,
        enabled: Bool = true
    ) -> DockMagneticSnap {
        guard enabled, frame.width > 0, frame.height > 0, threshold > 0, threshold.isFinite else {
            return .free(frame)
        }

        let vertical = snapAxis(
            low: frame.minX, mid: frame.midX, high: frame.maxX,
            targets: verticalTargets(screens: screens, peers: peers),
            threshold: threshold
        )
        let horizontal = snapAxis(
            low: frame.minY, mid: frame.midY, high: frame.maxY,
            targets: horizontalTargets(screens: screens, peers: peers),
            threshold: threshold
        )

        var origin = frame.origin
        if let vertical { origin.x += vertical.delta }
        if let horizontal { origin.y += horizontal.delta }
        let snapped = CGRect(origin: origin, size: frame.size)

        var guides: [DockMagneticGuide] = []
        if let vertical {
            for match in vertical.matches {
                let span = unionSpan(snapped.minY, snapped.maxY, match.spanStart, match.spanEnd)
                guides.append(DockMagneticGuide(
                    axis: .vertical, position: match.position,
                    start: span.lower, end: span.upper, kind: match.kind
                ))
            }
        }
        if let horizontal {
            for match in horizontal.matches {
                let span = unionSpan(snapped.minX, snapped.maxX, match.spanStart, match.spanEnd)
                guides.append(DockMagneticGuide(
                    axis: .horizontal, position: match.position,
                    start: span.lower, end: span.upper, kind: match.kind
                ))
            }
        }
        return DockMagneticSnap(frame: snapped, guides: guides)
    }

    fileprivate struct AxisTarget: Equatable {
        var position: CGFloat
        var kind: DockMagneticGuide.Kind
        var spanStart: CGFloat
        var spanEnd: CGFloat
    }

    fileprivate struct AxisSnap {
        var delta: CGFloat
        var matches: [AxisTarget]
    }

    /// Treat distances within half a point as the same snap so an edge and a peer can share a guide.
    private static let coincidence: CGFloat = 0.5

    private static func snapAxis(
        low: CGFloat, mid: CGFloat, high: CGFloat,
        targets: [AxisTarget],
        threshold: CGFloat
    ) -> AxisSnap? {
        var best: CGFloat?
        var matches: [AxisTarget] = []
        for target in targets where target.position.isFinite {
            for source in [low, mid, high] where source.isFinite {
                let delta = target.position - source
                let distance = abs(delta)
                guard distance <= threshold else { continue }
                if let current = best {
                    if distance + coincidence < abs(current) {
                        best = delta
                        matches = [target]
                    } else if abs(distance - abs(current)) <= coincidence, abs(delta - current) <= coincidence {
                        if !matches.contains(where: { $0.position == target.position && $0.kind == target.kind }) {
                            matches.append(target)
                        }
                    }
                } else {
                    best = delta
                    matches = [target]
                }
            }
        }
        guard let best else { return nil }
        return AxisSnap(delta: best, matches: matches)
    }

    private static func verticalTargets(screens: [CGRect], peers: [CGRect]) -> [AxisTarget] {
        screens.filter { !$0.isNull && $0.width > 0 }.flatMap { screen in
            [
                AxisTarget(position: screen.minX, kind: .edge, spanStart: screen.minY, spanEnd: screen.maxY),
                AxisTarget(position: screen.maxX, kind: .edge, spanStart: screen.minY, spanEnd: screen.maxY),
            ]
        } + peers.filter { !$0.isNull && $0.width > 0 }.flatMap { peer in
            [
                AxisTarget(position: peer.minX, kind: .peer, spanStart: peer.minY, spanEnd: peer.maxY),
                AxisTarget(position: peer.midX, kind: .peer, spanStart: peer.minY, spanEnd: peer.maxY),
                AxisTarget(position: peer.maxX, kind: .peer, spanStart: peer.minY, spanEnd: peer.maxY),
            ]
        }
    }

    private static func horizontalTargets(screens: [CGRect], peers: [CGRect]) -> [AxisTarget] {
        screens.filter { !$0.isNull && $0.height > 0 }.flatMap { screen in
            [
                AxisTarget(position: screen.minY, kind: .edge, spanStart: screen.minX, spanEnd: screen.maxX),
                AxisTarget(position: screen.maxY, kind: .edge, spanStart: screen.minX, spanEnd: screen.maxX),
            ]
        } + peers.filter { !$0.isNull && $0.height > 0 }.flatMap { peer in
            [
                AxisTarget(position: peer.minY, kind: .peer, spanStart: peer.minX, spanEnd: peer.maxX),
                AxisTarget(position: peer.midY, kind: .peer, spanStart: peer.minX, spanEnd: peer.maxX),
                AxisTarget(position: peer.maxY, kind: .peer, spanStart: peer.minX, spanEnd: peer.maxX),
            ]
        }
    }

    private static func unionSpan(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat)
        -> (lower: CGFloat, upper: CGFloat) {
        (min(a0, a1, b0, b1), max(a0, a1, b0, b1))
    }
}
