import CoreGraphics
import SwiftUI

/// The arc a saved exhibit follows from its hero frame into a dock tile.
///
/// Frames are in the stage panel's top-left-origin space, like every other exhibit pose. The picture
/// is tossed away from the dock edge and falls into the tile along a quadratic Bézier, shrinking as
/// it goes, so it reads as one object landing somewhere findable. The pose is a pure function of
/// `progress`, which the view animates frame by frame; the path never re-lays out the full-size image.
nonisolated struct WindowPeekStowPath: Equatable, Sendable {
    /// Share of the tile the picture still covers when it lands.
    static let landingShare: CGFloat = 0.62
    /// How the flight is timed. Slow out of the hero, quick into the tile.
    static let animation = Animation.timingCurve(0.42, 0, 0.3, 1, duration: 0.72)

    let hero: CGRect
    /// The dock tile's frame.
    let tile: CGRect
    let edge: DockEdge

    /// The picture's frame on landing: the hero's aspect ratio, centered in the tile.
    var landing: CGRect {
        let bounds = tile.width * Self.landingShare
        let fit = min(bounds / max(1, hero.width), bounds / max(1, hero.height))
        let size = CGSize(width: hero.width * fit, height: hero.height * fit)
        return CGRect(x: tile.midX - size.width / 2, y: tile.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// Unit vector pointing away from the dock edge, in top-left space (y grows downward).
    private var outward: CGVector {
        switch edge {
        case .bottom: CGVector(dx: 0, dy: -1)
        case .top: CGVector(dx: 0, dy: 1)
        case .left: CGVector(dx: 1, dy: 0)
        case .right: CGVector(dx: -1, dy: 0)
        }
    }

    /// The Bézier control point. It sits past the start, away from the dock, so the picture first
    /// rises slightly and then falls onto the tile. The lift grows with the distance but stays modest
    /// so a short flight is not a loop.
    var control: CGPoint {
        let start = CGPoint(x: hero.midX, y: hero.midY)
        let end = CGPoint(x: tile.midX, y: tile.midY)
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let distance = hypot(end.x - start.x, end.y - start.y)
        let lift = min(140, max(36, distance * 0.18))
        // How much further from the dock the start is than the midpoint.
        let ahead = max(0, (start.x - mid.x) * outward.dx + (start.y - mid.y) * outward.dy)
        return CGPoint(x: mid.x + outward.dx * (ahead + lift), y: mid.y + outward.dy * (ahead + lift))
    }

    /// The picture's frame at `progress` (0 at the hero, 1 on the tile).
    ///
    /// Size shrinks geometrically and front-loaded, so most of the flight shows a card-sized picture
    /// rather than a huge one sweeping across the screen.
    func frame(at progress: CGFloat) -> CGRect {
        let t = min(1, max(0, progress))
        let start = CGPoint(x: hero.midX, y: hero.midY)
        let end = CGPoint(x: tile.midX, y: tile.midY)
        let c = control
        let u = 1 - t
        let center = CGPoint(x: u * u * start.x + 2 * u * t * c.x + t * t * end.x,
                             y: u * u * start.y + 2 * u * t * c.y + t * t * end.y)
        let finalScale = max(0.001, landing.width / max(1, hero.width))
        let shrink = 1 - (1 - t) * (1 - t)
        let scale = exp(log(finalScale) * shrink)
        let size = CGSize(width: hero.width * scale, height: hero.height * scale)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// Fully visible for most of the flight, then fades as it sinks into the tile.
    func opacity(at progress: CGFloat) -> Double {
        let fadeStart: CGFloat = 0.8
        guard progress > fadeStart else { return 1 }
        return Double(max(0, 1 - (progress - fadeStart) / (1 - fadeStart)))
    }

    /// The exhibit pose at `progress`, in the same terms as the card-to-hero flight.
    func pose(at progress: CGFloat) -> WindowPeekExhibitPose {
        let t = min(1, max(0, progress))
        let radius = WindowPeekExhibitPose.heroCornerRadius + (4 - WindowPeekExhibitPose.heroCornerRadius) * t
        let placed = WindowPeekExhibitPose.placing(hero: hero, at: frame(at: t), cornerRadius: radius)
        return WindowPeekExhibitPose(scale: placed.scale, offset: placed.offset, opacity: opacity(at: t),
                                     cornerRadius: placed.cornerRadius)
    }
}
