import SwiftUI

/// Flix Files' motion, from the approved mockup: one named spring per kind of movement, and the
/// Reduce Motion replacement for each.
///
/// Views read Reduce Motion from `FlixPanelState.reduceMotion` (the panel) or the environment (the
/// dock tile) and pass it in; nothing here reads it. With Reduce Motion every spring becomes
/// ``fade``, and every transition that moves or scales becomes a plain crossfade.
enum FlixMotion {
    /// The panel opening: `response 0.34, dampingFraction 0.78`.
    static let panel = Animation.spring(response: 0.34, dampingFraction: 0.78)
    /// Rows that stay and slide to a new place.
    static let row = Animation.spring(response: 0.36, dampingFraction: 0.86)
    /// Rows, cards, and chips that arrive.
    static let arrive = Animation.spring(response: 0.34, dampingFraction: 0.85)
    static let sheet = Animation.spring(response: 0.32, dampingFraction: 0.84)
    static let toast = Animation.spring(response: 0.32, dampingFraction: 0.86)
    /// The drop question and a generated Smart Filter: a livelier settle.
    static let dialog = Animation.spring(response: 0.3, dampingFraction: 0.7)
    /// A selection pill sliding to its new row.
    static let pill = Animation.spring(response: 0.3, dampingFraction: 0.82)
    /// The search field growing out of its button.
    static let field = Animation.spring(response: 0.3, dampingFraction: 0.85)
    /// The tile's thumbnail and badge popping in.
    static let pop = Animation.spring(response: 0.38, dampingFraction: 0.55)
    /// Hover and press feedback.
    static let hover = Animation.easeOut(duration: 0.12)
    /// What every motion becomes with Reduce Motion.
    static let fade = Animation.easeOut(duration: 0.15)

    /// Rows on open rise one after another: 50 ms, then 14 ms apart, for the first twelve.
    static let staggerCount = 12
    static func staggerDelay(_ index: Int) -> Double { 0.05 + Double(index) * 0.014 }

    /// `animation`, or the crossfade with Reduce Motion.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }

    /// An arriving row, card, or chip: fades up eight points; leaves by fading. A crossfade with
    /// Reduce Motion.
    /// - Parameter index: The element's place among the first rows, which delays it 12 ms per row.
    static func rise(reduceMotion: Bool, index: Int? = nil) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertion = AnyTransition.opacity.combined(with: .offset(y: 8))
        guard let index, index > 0 else { return .asymmetric(insertion: insertion, removal: .opacity) }
        return .asymmetric(insertion: insertion.animation(arrive.delay(Double(min(index, 10)) * 0.012)),
                           removal: .opacity)
    }

    /// A chip or pill appearing in place: scales from 80 %. A crossfade with Reduce Motion.
    static func pop(reduceMotion: Bool, scale: CGFloat = 0.8) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: scale).combined(with: .opacity)
    }
}

/// The staggered entrance of the list's first elements while the panel springs open.
///
/// While the panel is in its entering pose the element waits seven points low and transparent; when
/// the panel is shown it rises with ``FlixMotion/row``, delayed by its index. Elements past the
/// first twelve, and everything with Reduce Motion, simply appear with the panel.
struct FlixEntrance: ViewModifier {
    /// The element's place from the top, or nil past the staggered ones.
    let index: Int?
    let phase: FlixPanelPhase
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let waiting = phase == .entering && !reduceMotion && index != nil
        content
            .opacity(waiting ? 0 : 1)
            .offset(y: waiting ? 7 : 0)
            // Replaces the panel's own spring for this element only, so each can carry its delay.
            .animation(index.map { FlixMotion.row.delay(FlixMotion.staggerDelay($0)) }, value: phase)
    }
}

extension View {
    /// Applies ``FlixEntrance``.
    func flixEntrance(_ index: Int?, state: FlixPanelState) -> some View {
        modifier(FlixEntrance(index: index.flatMap { $0 < FlixMotion.staggerCount ? $0 : nil },
                              phase: state.phase, reduceMotion: state.reduceMotion))
    }
}

extension FlixPanelState {
    /// The animation for a change inside the open panel: `animation`, the crossfade with Reduce
    /// Motion, or none while the panel is opening, closing, or hidden. The reset before an open
    /// (filter back to All Activity, search cleared) then snaps instead of sliding under the
    /// open spring.
    func motion(_ animation: Animation) -> Animation? {
        guard phase == .shown else { return nil }
        return reduceMotion ? FlixMotion.fade : animation
    }
}
