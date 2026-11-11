import CoreGraphics
import Foundation

/// The parts of a display Vapor's geometry needs, in AppKit global coordinates (points, y up,
/// origin at the primary display's lower-left corner; other displays can have negative origins).
nonisolated struct VaporDisplay: Equatable, Sendable {
    /// The persistent display identity (`DisplaySnapshot.id`), never a screen index.
    let id: String
    let frame: CGRect
    let visibleFrame: CGRect
    let isPrimary: Bool
}

/// How the orb is lit by its display's virtual lamp, which sits just above the middle of the
/// display's top edge. Recomputed only when the orb moves.
nonisolated struct VaporLighting: Equatable, Sendable {
    /// Direction from the orb's centre to the lamp, in radians. 0 points straight up; positive
    /// values lean toward the right. Apply it with SwiftUI's `rotationEffect(.radians(angle))` to
    /// a highlight drawn at the top of the orb.
    var angle: Double
    /// Highlight strength, 0.5…1.15. It falls off with distance from the lamp.
    var intensity: Double
    /// Contact shadow offset away from the lamp, in SwiftUI points (y down; always 0 vertically).
    var shadowOffset: CGSize
    /// Horizontal stretch for the contact shadow, 1…1.25, larger when the lamp is off to a side.
    var shadowStretch: Double

    /// Light from straight above, for previews.
    static let overhead = VaporLighting(angle: 0, intensity: 1, shadowOffset: .zero, shadowStretch: 1)
}

/// Which of the orb's top corners holds the count badge.
nonisolated enum VaporBadgeCorner: Equatable, Sendable {
    case topLeading, topTrailing
}

/// Where the suggestion bubbles and their capsule go, inside the suggestions window. The
/// window's frame depends only on where the orb is, not on how many bubbles there are.
nonisolated struct VaporSatelliteLayout: Equatable, Sendable {
    /// The suggestions window's frame in AppKit global coordinates.
    var windowFrame: CGRect
    /// Bubble centres, in the window's SwiftUI coordinates (origin top-left, y down).
    var bubbleCenters: [CGPoint]
    /// The centre of the room reserved for the capsule, in the window's SwiftUI coordinates.
    var capsuleCenter: CGPoint
    /// Which side of that room faces the orb, each component in -1…1 (SwiftUI axes): `dx` -1
    /// means the orb is to the capsule's right, so a narrower capsule sits flush right.
    var capsuleLean: CGVector
    /// The orb's centre in the same coordinates. Bubbles spring out of it and fly back into it.
    var orbCenter: CGPoint

    static let empty = VaporSatelliteLayout(windowFrame: .zero, bubbleCenters: [], capsuleCenter: .zero,
                                            capsuleLean: .zero, orbCenter: .zero)
}

/// How close an in-flight file drag is to the orb, for the lean and glow.
nonisolated struct VaporDropProximity: Equatable, Sendable {
    /// 0 when the drag is 190 pt or more beyond the orb's edge, rising (quadratically) to 1 at the edge.
    var value: Double
    /// The drag is over the orb or within 26 pt of its edge, where a drop lands in it.
    var isOverOrb: Bool
    /// How far the orb's contents lean toward the pointer, up to 7 pt, in SwiftUI coordinates.
    var lean: CGSize

    static let none = VaporDropProximity(value: 0, isOverOrb: false, lean: .zero)
}
