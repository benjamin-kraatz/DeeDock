import CoreGraphics
import Foundation

/// Timing and path for the hover label's flight into Window Peek's notice strip.
///
/// The constants are the values tuned in `docs/mockups/peek-notification-merge.html`. The spring is
/// SwiftUI's `.spring(response: 0.42, dampingFraction: 0.82)` evaluated analytically, so one
/// display-link clock can drive the flight, the strip's reveal, and the panel's growth from the same
/// sample. Separate SwiftUI animations in two windows would drift apart.
nonisolated enum WindowPeekNoticeMotion {
    /// Peek's panel fades in first; the label leaves this long after Peek appears.
    static let handOffDelay: Double = 0.06
    static let response: Double = 0.42
    static let dampingFraction: Double = 0.82
    /// How long the red edge that marks the landing takes to fade.
    static let glintDuration: Double = 0.52

    /// The spring's step response `t` seconds after the hand-off: 0 at the label, 1 at the strip.
    /// Underdamped, so it briefly passes 1 before settling.
    static func progress(at t: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        let zeta = dampingFraction
        guard zeta < 1 else { return 1 - exp(-omega * t) * (1 + omega * t) }
        let damped = omega * (1 - zeta * zeta).squareRoot()
        return 1 - exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
    }

    /// When the flight is indistinguishable from rest (within 0.3 %), and the strip takes over.
    static let settleTime: Double = {
        var last = 0.0
        for step in 0..<2_000 {
            let t = Double(step) * 0.002
            if abs(1 - progress(at: t)) > 0.003 { last = t }
        }
        return last + 0.002
    }()

    /// When the flight first covers 95 % of the way; the landing edge starts to glow here.
    static let glintStart: Double = {
        var t = 0.0
        while progress(at: t) < 0.95, t < 4 { t += 0.002 }
        return t
    }()

    /// When the flight and the landing glow are both over.
    static var duration: Double { max(settleTime, glintStart + glintDuration) }

    /// The flying banner's frame at `progress`, in a top-left-origin space shared by both rects.
    ///
    /// Position follows the raw spring, so it overshoots a little like the mockup; size uses the
    /// clamped value, because an overshooting size would open a gap around the strip. The path bows
    /// sideways by up to 22 % of the distance, never less than 26 points: upward when the travel is
    /// mostly horizontal, otherwise toward +x.
    static func flightFrame(from start: CGRect, to end: CGRect, progress: Double) -> CGRect {
        let p = CGFloat(progress)
        let clamped = min(max(p, 0), 1)
        var x = start.minX + (end.minX - start.minX) * p
        var y = start.minY + (end.minY - start.minY) * p
        let width = start.width + (end.width - start.width) * clamped
        let height = start.height + (end.height - start.height) * clamped
        let dx = end.midX - start.midX, dy = end.midY - start.midY
        let distance = hypot(dx, dy)
        if distance > 0 {
            var normal = CGVector(dx: -dy / distance, dy: dx / distance)
            let flip = abs(normal.dy) > 0.2 ? normal.dy > 0 : normal.dx < 0
            if flip { normal = CGVector(dx: -normal.dx, dy: -normal.dy) }
            let bow = max(0.22 * distance, 26) * lift(progress: progress)
            x += normal.dx * bow
            y += normal.dy * bow
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 0 at both ends of the flight and 1 halfway: drives the arc, the lift shadow, and a slight scale.
    static func lift(progress: Double) -> CGFloat {
        CGFloat(sin(Double.pi * min(max(progress, 0), 1)))
    }

    /// The landing edge's strength `t` seconds after the hand-off, 0 outside its fade.
    static func glint(at t: Double) -> Double {
        let age = t - glintStart
        guard age >= 0, age < glintDuration else { return 0 }
        return pow(1 - age / glintDuration, 2) * 0.9
    }

    /// Eases `value` from 0 at `lower` to 1 at `upper`, flat at both ends.
    static func smoothstep(_ lower: Double, _ upper: Double, _ value: Double) -> Double {
        let t = min(max((value - lower) / (upper - lower), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
