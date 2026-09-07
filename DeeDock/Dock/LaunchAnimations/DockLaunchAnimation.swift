import Foundation

/// Saved launch artwork presets. Motion stays inside the dock's existing inward envelope.
enum DockLaunchAnimation: String, Codable, CaseIterable, Identifiable {
    case bounce, spring, pulse, wobble, flip, none

    var id: Self { self }
    var duration: TimeInterval { 1.2 }

    var title: LocalizedStringResource {
        switch self {
        case .bounce: .launchAnimationBounce
        case .spring: .launchAnimationSpring
        case .pulse: .launchAnimationPulse
        case .wobble: .launchAnimationWobble
        case .flip: .launchAnimationFlip
        case .none: .launchAnimationNone
        }
    }

    /// One cycle begins and ends at rest; displacement is in points, inward from any dock edge.
    func pose(at progress: Double, size: CGFloat) -> Pose {
        let t = min(1, max(0, progress))
        let envelope = pow(sin(.pi * t), 2)
        switch self {
        case .bounce:
            // Two ballistic arcs, with a smaller second hop and a quiet interval before repeating.
            let first = t < 0.5
            let u = first ? t / 0.5 : (t - 0.5) / 0.35
            let arc = (0...1).contains(u) ? 4 * u * (1 - u) : 0
            return Pose(lift: min(36, size * 0.42) * arc * (first ? 1 : 0.42))
        case .spring:
            let stretch = sin(4 * .pi * t) * envelope
            return Pose(lift: min(26, size * 0.3) * envelope,
                        scaleX: 1 - 0.13 * stretch, scaleY: 1 + 0.18 * stretch)
        case .pulse:
            return Pose(scaleX: 1 + 0.16 * envelope, scaleY: 1 + 0.16 * envelope)
        case .wobble:
            return Pose(rotation: 16 * sin(6 * .pi * t) * envelope)
        case .flip:
            return Pose(lift: min(18, size * 0.2) * envelope, flip: 360 * (t * t * (3 - 2 * t)))
        case .none:
            return Pose()
        }
    }

    struct Pose {
        var lift: CGFloat = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var rotation: Double = 0
        var flip: Double = 0
    }
}
