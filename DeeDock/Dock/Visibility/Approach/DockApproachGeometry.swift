import CoreGraphics
import Foundation

/// How strongly the pointer lights the approach glow at one moment.
struct DockApproachSample: Equatable {
    /// Base strength in 0...1. Eases in from ``DockApproachGeometry/reach`` and reaches one at the zone.
    var intensity: Double
    /// Extra strength in 0...1 that grows exponentially over the last few dozen points before the zone.
    var surge: Double
    /// Canonical position along the edge the glow centers on, clamped to the zone.
    var focus: CGFloat
}

/// Where the approach glow is drawn and how strongly the pointer lights it, in AppKit screen points.
///
/// The band hugs the screen edge the dock is attached to and extends past both ends of the
/// activation zone far enough to hold the whole glow, so it never ends in a hard edge. With a ghost
/// dock it also grows to cover the resting dock, wherever that sits relative to the zone. Strength
/// depends on how far the pointer still is from the zone's inner boundary, so it peaks exactly
/// where a reveal can begin. This geometry is separate from ``DockActivationGeometry`` and never
/// captures events.
struct DockApproachGeometry: Equatable {
    /// Distance inward from the zone's inner boundary at which the glow starts to appear.
    static let reach: CGFloat = 200
    /// Distance past either end of the zone over which the pointer's effect fades out sideways.
    static let feather: CGFloat = 120
    /// The surge's e-folding distance: each further `surgeLength` points cuts the surge to about 37%.
    static let surgeLength: CGFloat = 24
    /// Depth of the glow at full base intensity. The surge grows it by up to ``surgeGrowth``.
    static let washDepth: CGFloat = 96
    /// How much taller and wider the glow gets at full surge.
    static let surgeGrowth: CGFloat = 0.35
    /// Room around the ghost dock: it rises this far into place and its outline must not touch the band's faded ends.
    static let ghostMargin: CGFloat = 16

    let edge: DockEdge
    /// The glow window in AppKit screen coordinates (y up, origin may be negative).
    let frame: CGRect
    /// The zone's span along the edge, in the band's canonical coordinates.
    ///
    /// Canonical x follows ``DockEdge/along(_:)`` in top-left coordinates: left to right on
    /// horizontal edges, top to bottom on vertical ones, starting at the band's own origin.
    let zoneSpan: ClosedRange<CGFloat>
    private let screen: CGRect
    /// Distance from the screen edge to the zone's inner boundary.
    private let zoneInner: CGFloat

    /// Half the glow's width along the edge at base intensity, for a zone of the given length.
    static func washHalfWidth(zoneLength: CGFloat) -> CGFloat { max(140, zoneLength * 0.55) }

    /// - Parameter ghost: The resting dock's bounds in the same space, when the ghost dock is shown.
    ///   The band grows to hold it, however far the dock sits from the edge or the zone.
    init(screen: CGRect, zone: CGRect, edge: DockEdge, ghost: CGRect? = nil) {
        self.edge = edge
        self.screen = screen
        let ghost = ghost.flatMap { $0.isNull || $0.isEmpty ? nil : $0.insetBy(dx: -Self.ghostMargin, dy: -Self.ghostMargin) }
        // Inward extent of the ghost from the screen edge, including the room it rises through.
        let ghostDepth: CGFloat = ghost.map {
            switch edge {
            case .bottom: $0.maxY - screen.minY
            case .top: screen.maxY - $0.minY
            case .left: $0.maxX - screen.minX
            case .right: screen.maxX - $0.minX
            }
        } ?? 0
        let depth = min(max(Self.washDepth * (1 + Self.surgeGrowth), ghostDepth), edge.depth(of: screen.size))
        // The glow centers inside the zone, so it can extend one full surged half-width past
        // either end. A narrower band clipped it into a visible vertical cut.
        let margin = Self.washHalfWidth(zoneLength: edge.length(of: zone.size)) * (1 + Self.surgeGrowth)
        switch edge {
        case .bottom, .top:
            let lo = max(screen.minX, min(zone.minX - margin, ghost?.minX ?? .infinity))
            let hi = min(screen.maxX, max(zone.maxX + margin, ghost?.maxX ?? -.infinity))
            frame = CGRect(x: lo, y: edge == .bottom ? screen.minY : screen.maxY - depth, width: max(0, hi - lo), height: depth)
            zoneSpan = (zone.minX - lo)...(max(zone.minX, zone.maxX) - lo)
            zoneInner = edge == .bottom ? zone.maxY - screen.minY : screen.maxY - zone.minY
        case .left, .right:
            let lo = max(screen.minY, min(zone.minY - margin, ghost?.minY ?? .infinity))
            let hi = min(screen.maxY, max(zone.maxY + margin, ghost?.maxY ?? -.infinity))
            frame = CGRect(x: edge == .left ? screen.minX : screen.maxX - depth, y: lo, width: depth, height: max(0, hi - lo))
            // Canonical x runs top to bottom, opposite AppKit's y axis.
            zoneSpan = (hi - zone.maxY)...(max(hi - zone.maxY, hi - zone.minY))
            zoneInner = edge == .left ? zone.maxX - screen.minX : screen.maxX - zone.minX
        }
    }

    /// Band length along the edge and depth into the screen.
    var length: CGFloat { edge.length(of: frame.size) }
    var depth: CGFloat { edge.depth(of: frame.size) }

    /// Converts an AppKit screen rect (y up, origin may be negative) to the band's top-left view coordinates.
    ///
    /// Unlike canonical coordinates this keeps the screen's orientation, so artwork drawn in the
    /// result stays upright on every edge.
    func localRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX - frame.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The glow's strength and center for a pointer in AppKit screen coordinates.
    ///
    /// A pointer on another display, beyond ``reach``, or more than ``feather`` past either end of
    /// the zone yields zero. Inside the zone, or between it and the screen edge, yields full
    /// intensity and full surge.
    func sample(pointer: CGPoint) -> DockApproachSample {
        let along = canonicalAlong(pointer)
        let focus = min(max(along, zoneSpan.lowerBound), zoneSpan.upperBound)
        // Accept the edge row itself: AppKit reports the pointer at maxY - 1 or maxY on the top edge.
        guard screen.insetBy(dx: -1, dy: -1).contains(pointer), length > 0 else {
            return DockApproachSample(intensity: 0, surge: 0, focus: focus)
        }
        let remaining = max(0, inward(pointer) - zoneInner)
        let proximity = 1 - min(1, remaining / Self.reach)
        let outside = along < zoneSpan.lowerBound ? zoneSpan.lowerBound - along
            : along > zoneSpan.upperBound ? along - zoneSpan.upperBound : 0
        let lateral = Self.smoothstep(1 - min(1, outside / Self.feather))
        return DockApproachSample(intensity: Double(Self.smoothstep(proximity) * lateral),
                                  surge: Double(Self.surge(remaining: remaining) * lateral), focus: focus)
    }

    /// Exponential decay with distance, rescaled so it is exactly zero at ``reach`` and one at the zone.
    private static func surge(remaining: CGFloat) -> CGFloat {
        guard remaining < reach else { return 0 }
        let tail = exp(-reach / surgeLength)
        return (exp(-remaining / surgeLength) - tail) / (1 - tail)
    }

    private func inward(_ point: CGPoint) -> CGFloat {
        switch edge {
        case .bottom: point.y - screen.minY
        case .top: screen.maxY - point.y
        case .left: point.x - screen.minX
        case .right: screen.maxX - point.x
        }
    }

    private func canonicalAlong(_ point: CGPoint) -> CGFloat {
        edge.isVertical ? frame.maxY - point.y : point.x - frame.minX
    }

    /// Eases in so the glow does not pop at the reach boundary; the surge supplies the final rise.
    private static func smoothstep(_ t: CGFloat) -> CGFloat { t * t * (3 - 2 * t) }
}
