import CoreGraphics

/// The geometry of swipe-to-clear, kept apart from event handling so it can be tested.
///
/// Distances are in points. A row's *reveal* is how far it has moved left to uncover the red
/// Clear action behind its trailing edge; zero means closed.
nonisolated enum NotificationFeedSwipePhysics {
    /// Width of the revealed Clear action. A short swipe snaps open to exactly this.
    static let actionWidth: CGFloat = 72
    /// A swipe past this fraction of the row's width clears it on release.
    static let commitFraction: CGFloat = 0.4
    /// Leftward release speed, in points per second, that clears regardless of distance.
    static let flickSpeed: CGFloat = 1100
    /// Release speed above which a half-open row closes instead of snapping open, in points per
    /// second toward the right.
    static let snapBackSpeed: CGFloat = 300
    /// Scale of the rubber band when the row is pulled right of its resting place.
    static let rubberBand: CGFloat = 28
    /// Fraction of the pointer movement a row follows once it is pulled past its own width.
    static let overshootFollow: CGFloat = 0.25
    /// Pointer travel before a gesture's direction is decided. Below it, nothing is claimed.
    static let intentDistance: CGFloat = 6
    /// Horizontal travel must exceed vertical travel by this factor to claim the gesture, so a
    /// slightly diagonal scroll keeps scrolling the list.
    static let horizontalDominance: CGFloat = 1.5
    /// The label appears once the action is this wide.
    static let labelThreshold: CGFloat = actionWidth * 0.45

    /// What a gesture's travel means.
    enum Intent: Equatable {
        case horizontal, vertical
    }

    /// What a released row does.
    enum Outcome: Equatable {
        /// Fly out and remove the row (or the whole stack).
        case commit
        /// Rest open at ``actionWidth`` with the action showing.
        case reveal
        /// Slide back closed.
        case close
    }

    /// The direction a gesture means once it has travelled far enough, or nil while undecided.
    /// - Parameters:
    ///   - dx: Accumulated horizontal travel.
    ///   - dy: Accumulated vertical travel.
    static func intent(dx: CGFloat, dy: CGFloat) -> Intent? {
        guard (dx * dx + dy * dy).squareRoot() >= intentDistance else { return nil }
        return abs(dx) > abs(dy) * horizontalDominance ? .horizontal : .vertical
    }

    /// The reveal for a gesture's travel.
    /// - Parameters:
    ///   - start: The reveal when the gesture began: zero, or ``actionWidth`` for an open row.
    ///   - translation: Horizontal content travel since the start; negative is leftward.
    ///   - width: The row's width.
    /// - Returns: Positive while revealing. Negative values are a damped pull to the right.
    static func reveal(start: CGFloat, translation: CGFloat, width: CGFloat) -> CGFloat {
        let raw = start - translation
        if raw < 0 {
            // Rubber band: the further right, the less the row follows.
            return -(abs(raw) / (1 + abs(raw) / rubberBand))
        }
        if raw > width { return width + (raw - width) * overshootFollow }
        return raw
    }

    /// What the row does on release.
    /// - Parameters:
    ///   - reveal: The reveal at release.
    ///   - width: The row's width.
    ///   - velocity: Horizontal content speed in points per second; negative is leftward.
    static func outcome(reveal: CGFloat, width: CGFloat, velocity: CGFloat) -> Outcome {
        if reveal >= width * commitFraction || velocity < -flickSpeed { return .commit }
        if reveal > actionWidth * 0.5, velocity <= snapBackSpeed { return .reveal }
        return .close
    }
}
