import CoreGraphics
import Foundation

/// Where the startled face is at one moment: how wide the eyes are, how small and raised the
/// pupils, how round the mouth, and the little squash and hop of the whole face.
///
/// The expression snaps on over the first 80 ms, holds, and lets go over the last half of
/// `RobiSurprise.duration`, so the face is back to normal by the time the controller clears the
/// state. The squash is a damped bounce that starts the moment the piece hits from below: the face
/// flattens and lifts, rebounds past its shape once, and settles within 0.3 s. `gentle`, for
/// Reduce Motion, keeps only a smaller eye-widen and the round mouth.
struct RobiSurpriseFrame {
    /// Scale of each eye, 1 at rest.
    let eyeScale: CGFloat
    /// Scale of each pupil, 1 at rest; smaller is the stare.
    let pupilScale: CGFloat
    /// How far the pupils have jumped to the middle and up, 0…1.
    let stare: Double
    /// The round mouth, 0…1.
    let mouth: Double
    /// The face's squash: wider and shorter when hit.
    let scale: CGSize
    /// The face's hop, in points; negative is up.
    let lift: CGFloat

    init(_ surprise: RobiSurprise, at date: Date, gentle: Bool) {
        let elapsed = min(RobiSurprise.duration, max(0, date.timeIntervalSince(surprise.start)))
        let hit = Self.smooth(min(1, elapsed / 0.08))
        let hold: TimeInterval = 0.28
        let release = elapsed < hold ? 1 : 1 - Self.smooth((elapsed - hold) / (RobiSurprise.duration - hold))
        let amount = hit * release
        // The recoil: a damped sine that goes positive first, peaking around 40 ms at about 0.66.
        let recoil = gentle ? 0 : exp(-elapsed / 0.11) * sin(2 * .pi * elapsed / 0.2)
        eyeScale = 1 + (gentle ? 0.12 : 0.3) * amount + 0.08 * recoil
        pupilScale = 1 - (gentle ? 0 : 0.3) * amount
        stare = gentle ? 0 : amount
        mouth = amount
        scale = CGSize(width: 1 + 0.08 * recoil, height: 1 - 0.14 * recoil)
        lift = -2.5 * recoil
    }

    /// The pupils' offset: the pointer's glance pulled to the middle and a little up by `stare`.
    /// Offsets are in tenths of an eye width with y pointing down, as in `RobiEyes.pupil`.
    func pupil(from glance: CGSize) -> CGSize {
        CGSize(width: glance.width * (1 - stare), height: glance.height * (1 - stare) - 1.0 * stare)
    }

    private static func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
}
