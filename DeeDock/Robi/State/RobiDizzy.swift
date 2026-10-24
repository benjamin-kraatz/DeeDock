import Foundation

/// Robi spinning its eyes after the pointer circled its face: a small easter egg.
struct RobiDizzy: Equatable {
    /// When the spin started. The face animates from here for `duration`.
    let start: Date
    /// The way the pointer went round, on screen. The left pupil spins this way and the right
    /// one the other way, like a cartoon character seeing stars.
    let clockwise: Bool

    static let duration: TimeInterval = 1.8
    /// How many times the pupils go round before they settle.
    static let rounds: Double = 2.5
}

/// Notices the pointer drawing a full circle around Robi's face.
///
/// Pointer positions come in as offsets from the face's centre in AppKit points (y up). The
/// detector adds up the angle the pointer sweeps around the face. A full turn in one direction,
/// within `window` seconds and without leaving the ring around the face, counts as a circle.
/// Small backward wobbles are forgiven; a real reversal, a pause, or straying too close or too
/// far starts over.
struct RobiCircleDetector {
    /// The ring the pointer must stay in, in points from the face's centre.
    static let ring: ClosedRange<Double> = 24...260
    /// A full turn has to happen within this long.
    static let window: TimeInterval = 3
    /// A gap between pointer events longer than this starts over.
    static let pause: TimeInterval = 0.5
    /// A backward step smaller than this, in radians, is jitter rather than a reversal.
    static let jitter: Double = 0.15

    private var lastAngle: Double?
    private var lastTime = Date.distantPast
    private var started = Date.distantPast
    private var turned: Double = 0

    mutating func reset() {
        lastAngle = nil
        turned = 0
    }

    /// Adds one pointer position. Returns whether the pointer just completed a circle, and which
    /// way: `true` for clockwise on screen. The count starts over after a circle.
    mutating func add(dx: Double, dy: Double, at now: Date) -> Bool? {
        let distance = hypot(dx, dy)
        guard Self.ring.contains(distance) else { reset(); return nil }
        let angle = atan2(dy, dx)
        defer { lastAngle = angle; lastTime = now }
        guard let lastAngle, now.timeIntervalSince(lastTime) < Self.pause else {
            turned = 0
            started = now
            return nil
        }
        var delta = angle - lastAngle
        if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
        if turned != 0, (delta > 0) != (turned > 0), abs(delta) > Self.jitter {
            turned = 0
            started = now
        }
        if turned == 0 { started = now }
        turned += delta
        if now.timeIntervalSince(started) > Self.window {
            turned = delta
            started = now
        }
        guard abs(turned) >= 2 * .pi else { return nil }
        // AppKit's y axis points up, so a growing angle is counterclockwise on screen.
        let clockwise = turned < 0
        turned = 0
        return clockwise
    }
}
