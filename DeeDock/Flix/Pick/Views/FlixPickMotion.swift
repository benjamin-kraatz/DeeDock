import SwiftUI

/// Flix Pick's motion, from the approved mockup (`docs/mockups/flix-pick.html`, style Tuck).
///
/// `FlixPickPanelController` and the views read Reduce Motion from `FlixPickState.reduceMotion`;
/// nothing here reads it. With Reduce Motion nothing slides, scales, or springs: the panel and its
/// text fade, and the rail changes width at once.
///
/// Every animation here runs because a state value changed (shown, open, pressed). None is driven
/// by pointer moves.
enum FlixPickMotion {
    /// The panel settling beside the picker: the mockup's 0.42 s `cubic-bezier(.2, 1.1, .3, 1)`,
    /// as a spring so an early exit takes over smoothly.
    static let arrive = Animation.spring(response: 0.36, dampingFraction: 0.78)
    /// The panel's fade in, shorter than its slide.
    static let fadeIn = Animation.easeOut(duration: 0.22)
    /// Leaving with the picker: a quick fade while it eases back toward the picker.
    static let leave = Animation.easeOut(duration: 0.18)
    /// The rail springing open (the mockup's 0.32 s width curve) with a slight settle.
    static let open = Animation.spring(response: 0.32, dampingFraction: 0.84)
    /// The rail closing: a little quicker, without the settle, and a beat after the text starts
    /// to fade, so the text leaves first instead of being cut off by the edge.
    static let close = Animation.spring(response: 0.28, dampingFraction: 0.92).delay(0.05)
    /// Text arrives shortly after the width starts to grow, and leaves at once.
    static let textIn = Animation.easeOut(duration: 0.2).delay(0.08)
    static let textOut = Animation.easeOut(duration: 0.12)

    /// How far the panel slides in from the picker, and how small it starts.
    static let slide: CGFloat = 12
    static let entranceScale: CGFloat = 0.98
    /// A pressed row.
    static let pressScale: CGFloat = 0.985
    /// How long a row keeps its pressed look after a click, so a quick click still shows.
    static let hit: Duration = .milliseconds(160)
}

/// The panel's pose before it arrives and after it leaves: transparent, a few points toward the
/// picker, and slightly small. With Reduce Motion only the opacity changes.
///
/// The slide and scale take their own animation here. The opacity is left to the transaction
/// `FlixPickPanelController` opens, so the controller's completion follows the fade.
struct FlixPickEntrance: ViewModifier {
    let shown: Bool
    let side: FlixPickPlacement.Side
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let away = !shown && !reduceMotion
        // Toward the picker: left for a rail on its right, right for one on its left.
        let towardPicker = side == .right ? -FlixPickMotion.slide : FlixPickMotion.slide
        content
            .scaleEffect(away ? FlixPickMotion.entranceScale : 1, anchor: side == .right ? .leading : .trailing)
            .offset(x: away ? towardPicker : 0)
            .animation(shown ? FlixPickMotion.arrive : FlixPickMotion.leave, value: shown)
            .opacity(shown ? 1 : 0)
    }
}

/// Fades text in as the rail opens (shortly after its width starts to grow) and out at once as it
/// closes. Only opacity changes, so it is the same with Reduce Motion.
struct FlixPickTextReveal: ViewModifier {
    let open: Bool

    func body(content: Content) -> some View {
        content
            .opacity(open ? 1 : 0)
            // Replaces the rail's spring for the text only.
            .animation(open ? FlixPickMotion.textIn : FlixPickMotion.textOut, value: open)
    }
}

extension View {
    /// Applies ``FlixPickTextReveal``.
    func flixPickReveal(_ open: Bool) -> some View { modifier(FlixPickTextReveal(open: open)) }
}
