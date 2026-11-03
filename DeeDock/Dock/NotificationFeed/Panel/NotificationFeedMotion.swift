import SwiftUI

/// The feed's shared timing, from the approved DEE-155 mockup.
///
/// One spring moves every row, stack, and fold. Under Reduce Motion nothing slides: rows take
/// their new places at once and every arrival, removal, and unfold is a 150 ms cross-fade, which
/// each transition carries itself. The swipe gesture still follows the pointer, because that
/// motion is the person's own, and settles with the 150 ms curve.
enum NotificationFeedMotion {
    /// Response 0.38 s, damping 0.82: settles in about 400 ms with a small overshoot.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
    static let reducedDuration = 0.15
    static let reduced = Animation.easeInOut(duration: reducedDuration)

    /// For a swipe settling open, closed, or back.
    static func standard(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : spring
    }

    /// For rows moving to new places: nil under Reduce Motion, so they move without sliding.
    static func layout(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : spring
    }

    /// Text fading in as a peeking card becomes a row, and out as it folds back. Under Reduce
    /// Motion it is the 150 ms cross-fade, the only thing that moves when a stack unfolds.
    static func contentFade(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : .easeOut(duration: 0.2)
    }

    /// The fade of a leaving row. It runs on its own ease-in instead of the spring, which would
    /// overshoot opacity and read as a flicker; the mockup fades every ghost this way.
    static let leaveFade = Animation.easeIn(duration: 0.32)

    /// How long an opened entry drops before the popover closes, so the drop reads before the
    /// panel fades. Matches the mockup's `min(260 ms, settle × 0.55)`.
    static func closeDelay(reduceMotion: Bool) -> Duration {
        reduceMotion ? .milliseconds(120) : .milliseconds(210)
    }

    /// How long a cleared group folds its rows before the front card starts to fade. The spring
    /// has the rows about 80 % tucked in by then, and ``leaveFade`` starts slowly, so the fold's
    /// tail and the fade overlap as they do in the mockup, where the rows converge and fade
    /// together.
    static func foldDelay(reduceMotion: Bool) -> Duration {
        reduceMotion ? .zero : .milliseconds(160)
    }

    /// Distance an opened entry travels toward the dock while it fades.
    static let dropDistance: CGFloat = 26
    /// Distance an arriving entry slides in from above.
    static let arrivalDistance: CGFloat = 22
}

/// How an entry leaves the feed. Chosen by the action that removed it.
///
/// SwiftUI takes a removed view's transition from its last rendered state, so the style is
/// staged on the panel a frame before the store drops the entry. See
/// `NotificationFeedCoordinator.removeAnimated(_:style:after:)`.
nonisolated enum NotificationFeedLeaveStyle: Equatable, Sendable {
    /// Shrinks to 92 % and fades. Remove, Clear All, and a cleared group after it folds.
    case shrink
    /// Drops toward the dock while it shrinks and fades: the app was opened.
    case drop
    /// Already flown out by a swipe; only the space it held closes.
    case swiped
}

extension NotificationFeedLeaveStyle {
    /// The transition for an entry or group leaving with this style.
    /// - Parameters:
    ///   - edge: The dock edge the popover is attached to; `drop` moves toward it.
    ///   - reduceMotion: Replaces every movement with a 150 ms cross-fade.
    func transition(edge: DockEdge, reduceMotion: Bool) -> AnyTransition {
        let arrival = AnyTransition.offset(y: -NotificationFeedMotion.arrivalDistance).combined(with: .opacity)
        if reduceMotion { return .opacity.animation(NotificationFeedMotion.reduced) }
        let removal: AnyTransition
        switch self {
        case .shrink:
            removal = AnyTransition.scale(scale: 0.92)
                .combined(with: AnyTransition.opacity.animation(NotificationFeedMotion.leaveFade))
        case .drop:
            let distance = NotificationFeedMotion.dropDistance
            let offset: CGSize = switch edge {
            case .bottom: CGSize(width: 0, height: distance)
            case .top: CGSize(width: 0, height: -distance)
            case .left: CGSize(width: -distance, height: 0)
            case .right: CGSize(width: distance, height: 0)
            }
            removal = AnyTransition.offset(offset).combined(with: .scale(scale: 0.86))
                .combined(with: AnyTransition.opacity.animation(NotificationFeedMotion.leaveFade))
        case .swiped:
            removal = .opacity.animation(.linear(duration: 0.01))
        }
        return .asymmetric(insertion: arrival, removal: removal)
    }
}
