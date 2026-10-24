import CoreGraphics
import Foundation

/// A picked region's flight from where it was drawn on the window up into Robi's face, and the
/// click-through overlay it flies in.
///
/// Everything is decided when the flight starts. The region arrives in window-local top-left
/// points, the window and the face in AppKit screen points (displays left of or above the primary
/// one are negative in both), and what the view draws is in the overlay's own top-left points:
/// the overlay's top-left corner is the origin and y grows downwards. The piece follows a
/// quadratic curve whose apex sits above the straight line, like a toss, shrinks on the way, and
/// fades once it reaches the face. With Reduce Motion it fades where it is and lands at once.
nonisolated struct RobiFlightPath: Equatable, Sendable {
    /// When the flight began.
    let start: Date
    /// With Reduce Motion the piece fades in place instead of flying.
    let reduceMotion: Bool
    /// The overlay panel's frame, in AppKit points: the window, the region and the face, with
    /// room around them for the arc and the piece's shadow.
    let overlayFrame: CGRect
    /// Where the piece starts: the region, in overlay points.
    let origin: CGRect
    /// Where it lands: the face's centre, in overlay points.
    let destination: CGPoint
    /// The curve's control point, in overlay points.
    let control: CGPoint

    /// The whole flight, from the first frame to the last of the fade.
    static let duration: TimeInterval = 0.5
    /// When the piece reaches the face. The face reacts then, while the piece is still fading.
    static let landing: TimeInterval = 0.26
    /// The fade in place with Reduce Motion.
    static let reducedDuration: TimeInterval = 0.28
    /// The piece as it slips into the face: smaller than the compact face, so it reads as taken in.
    static let landingSize = CGSize(width: 20, height: 13)
    /// Room kept around the union of window, region and face. The arc bows out by up to
    /// `maximumBow` and the shadow reaches a little further.
    private static let margin: CGFloat = 40
    private static let maximumBow: CGFloat = 48

    /// - Parameters:
    ///   - region: The picked rect, in window-local top-left points.
    ///   - window: The window, in AppKit points.
    ///   - face: The centre of Robi's face, in AppKit points.
    init(region: CGRect, window: CGRect, face: CGPoint, reduceMotion: Bool, start: Date = .now) {
        self.start = start
        self.reduceMotion = reduceMotion
        // Window-local top-left to AppKit: x shifts by the window's left edge; y flips around the
        // window's top edge, so the region's bottom in AppKit is its top-left maxY below that edge.
        let regionAppKit = CGRect(x: window.minX + region.minX, y: window.maxY - region.maxY,
                                  width: region.width, height: region.height)
        let faceBox = CGRect(x: face.x - 24, y: face.y - 24, width: 48, height: 48)
        let frame = window.union(regionAppKit).union(faceBox).insetBy(dx: -Self.margin, dy: -Self.margin).integral
        overlayFrame = frame
        // AppKit to overlay-local top-left: subtract the overlay's left edge, flip y around its top.
        origin = CGRect(x: regionAppKit.minX - frame.minX, y: frame.maxY - regionAppKit.maxY,
                        width: regionAppKit.width, height: regionAppKit.height)
        destination = CGPoint(x: face.x - frame.minX, y: frame.maxY - face.y)
        control = Self.control(from: CGPoint(x: origin.midX, y: origin.midY), to: destination)
    }

    /// Reduce Motion lands at once; otherwise the piece arrives at `landing`.
    var landing: TimeInterval { reduceMotion ? 0 : Self.landing }
    var duration: TimeInterval { reduceMotion ? Self.reducedDuration : Self.duration }

    /// The piece at one moment, in overlay points. After `duration` it is fully faded.
    func frame(at date: Date) -> RobiFlightFrame {
        let elapsed = max(0, date.timeIntervalSince(start))
        if reduceMotion {
            return RobiFlightFrame(rect: origin, cornerRadius: 6, lineWidth: 2,
                                   opacity: max(0, 1 - elapsed / Self.reducedDuration), lift: 0)
        }
        let progress = Self.progress(at: elapsed)
        // The spring overshoots by about 1 %. The position may follow it, but the size must not:
        // on a very wide selection 1 % past the landing size is a negative width.
        let shrink = min(1, max(0, progress))
        let size = CGSize(width: origin.width + (Self.landingSize.width - origin.width) * shrink,
                          height: origin.height + (Self.landingSize.height - origin.height) * shrink)
        let centre = point(at: progress)
        let fadeStart = Self.landing
        let opacity = elapsed < fadeStart ? 1 : max(0, 1 - (elapsed - fadeStart) / (Self.duration - fadeStart))
        // The shadow appears over the first tenth of a second: the moment the piece lifts off the sheet.
        let lift = Self.smooth(min(1, elapsed / 0.1))
        return RobiFlightFrame(rect: CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
                                            width: size.width, height: size.height),
                               cornerRadius: 6 - progress, lineWidth: 2 - 0.5 * progress, opacity: opacity, lift: lift)
    }

    /// The point `progress` of the way along the curve.
    func point(at progress: CGFloat) -> CGPoint {
        let p = min(1.08, max(0, progress)), q = 1 - p
        let from = CGPoint(x: origin.midX, y: origin.midY)
        return CGPoint(x: q * q * from.x + 2 * q * p * control.x + p * p * destination.x,
                       y: q * q * from.y + 2 * q * p * control.y + p * p * destination.y)
    }

    /// How far along the piece is: a spring with a 0.38 s response and a damping ratio of 0.82,
    /// which covers half the way in the first tenth of a second and arrives, with under one per
    /// cent of overshoot, at `landing`. 1 from `duration` on.
    static func progress(at elapsed: TimeInterval) -> CGFloat {
        guard elapsed < duration else { return 1 }
        let omega = 2 * Double.pi / 0.38, damping = 0.82
        let damped = omega * (1 - damping * damping).squareRoot()
        let decay = exp(-damping * omega * elapsed)
        return CGFloat(1 - decay * (cos(damped * elapsed) + damping * omega / damped * sin(damped * elapsed)))
    }

    /// The control point halfway along, pushed sideways so the arc's apex sits above the chord
    /// on screen (y down, so the normal with the smaller y). The bow grows with the distance and
    /// stops at `maximumBow`, so a pick next to the face barely curves and a far one arcs.
    private static func control(from: CGPoint, to: CGPoint) -> CGPoint {
        let dx = to.x - from.x, dy = to.y - from.y
        let distance = hypot(dx, dy)
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        guard distance > 1 else { return mid }
        var normal = CGPoint(x: -dy / distance, y: dx / distance)
        if normal.y > 0 || (normal.y == 0 && normal.x < 0) { normal = CGPoint(x: -normal.x, y: -normal.y) }
        let bow = min(maximumBow, distance * 0.18)
        return CGPoint(x: mid.x + normal.x * bow, y: mid.y + normal.y * bow)
    }

    private static func smooth(_ t: CGFloat) -> CGFloat { t * t * (3 - 2 * t) }
}

/// One frame of the flight: where the piece is and how it is drawn.
nonisolated struct RobiFlightFrame: Equatable, Sendable {
    /// The piece, in overlay top-left points.
    let rect: CGRect
    let cornerRadius: CGFloat
    /// The dashed outline's width; a little thinner as the piece shrinks.
    let lineWidth: CGFloat
    let opacity: Double
    /// How far the piece has lifted off the sheet, 0…1: the shadow's strength.
    let lift: CGFloat
}
