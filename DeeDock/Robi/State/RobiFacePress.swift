import CoreGraphics
import Foundation

/// What the face's press gesture reports to the controller. The controller reads the pointer
/// itself, because the panel moves under it while the tab is dragged.
enum RobiFaceGesture {
    /// The press began or the pointer moved while it is held.
    case changed
    /// The pointer was released.
    case ended
    /// SwiftUI ended the press without a release, such as when the view went away.
    case cancelled
}

/// One press on Robi's face, from mouse-down to release.
///
/// A press is a click until the pointer moves `RobiMetrics.dragThreshold` away from where it went
/// down. Past that, in a phase that allows it, it drags the tab along the window's top edge.
/// Points are AppKit screen points (`NSEvent.mouseLocation`), not the gesture's local space,
/// which moves with the panel.
nonisolated struct RobiFacePress: Equatable, Sendable {
    /// Where the pointer went down.
    let start: CGPoint
    /// False while selecting, when the tab stays put and the press can only click.
    let canDrag: Bool
    /// The pointer's x minus the tab centre's x at mouse-down. Keeping it constant makes the tab
    /// move 1:1 with the pointer instead of jumping its centre under it, which matters in the
    /// prompt bar, where the face sits at the bar's leading end.
    let grip: CGFloat
    /// True once the press has moved past the threshold and become a drag.
    var isDragging = false
    /// True once a Shift-drag started pulling a hanging tab away from the edge like goo, instead
    /// of moving it along the edge.
    var isStretching = false
    /// The tab's position along the edge while dragging, as in `RobiLayout.tabX`.
    var position: Double?
    /// The rubber-band offset while the pointer is past the end of the track.
    var stretch: CGFloat = 0

    /// True when the pointer has moved far enough from `start` to count as a drag.
    func hasLeftClickDistance(_ pointer: CGPoint) -> Bool {
        hypot(pointer.x - start.x, pointer.y - start.y) > RobiMetrics.dragThreshold
    }
}

/// The spring a rubber-banded tab settles back with after release: a light bounce that
/// overshoots by under a tenth of the stretch and is still after `duration`.
nonisolated enum RobiTabSpring {
    static let duration: TimeInterval = 0.5

    /// The share of the release stretch still applied `elapsed` seconds after release: 1 at
    /// release, 0 from `duration` on.
    static func remaining(after elapsed: TimeInterval) -> CGFloat {
        guard elapsed < duration else { return 0 }
        // An underdamped spring with a 0.3 s response and a damping ratio of 0.6.
        let omega = 2 * Double.pi / 0.3, damping = 0.6
        let damped = omega * (1 - damping * damping).squareRoot()
        return CGFloat(exp(-damping * omega * elapsed) * cos(damped * elapsed))
    }
}

/// The goo pull: how far a hanging tab is pulled away from the window's edge, and how far its
/// bulb leans sideways. Both resist more the further the pointer goes, like a rubber band, and
/// the release snaps back with a wobbly overshoot.
nonisolated enum RobiGoo {
    /// The most the tab can be pulled down, however far the pointer goes.
    static let pullLimit: CGFloat = 110
    /// The most the bulb can lean to either side.
    static let leanLimit: CGFloat = 40
    /// How far a snap-back may overshoot into a squash, in points.
    static let squashLimit: CGFloat = 8
    static let snapDuration: TimeInterval = 0.9

    /// The stretch for a pointer offset from where the press began (pointer y down positive).
    /// Each axis approaches its limit and never reaches it: the first points of the pull move the
    /// goo almost 1:1, later ones barely.
    static func stretch(for offset: CGSize) -> CGSize {
        CGSize(width: resist(offset.width, limit: leanLimit), height: max(0, resist(offset.height, limit: pullLimit)))
    }

    private static func resist(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        let sign: CGFloat = value < 0 ? -1 : 1
        return sign * limit * (1 - exp(-abs(value) / limit))
    }

    /// The share of the release stretch still applied `elapsed` seconds after release. A looser
    /// spring than `RobiTabSpring`: it overshoots past the edge once or twice, which reads as the
    /// goo snapping back. Callers clamp the negative pull to `squashLimit`.
    static func remaining(after elapsed: TimeInterval) -> CGFloat {
        guard elapsed < snapDuration else { return 0 }
        let omega = 2 * Double.pi / 0.32, damping = 0.32
        let damped = omega * (1 - damping * damping).squareRoot()
        return CGFloat(exp(-damping * omega * elapsed) * cos(damped * elapsed))
    }
}
