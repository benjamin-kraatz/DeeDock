import SwiftUI

/// Look and motion for Harbor, chosen in the interactive mockup (`docs/mockups/harbor.html`, DEE-119):
///
/// ```
/// HarborStyle(layout: .frontAppLarge, opening: .flyOut, closeButton: .leading, groupHighlight: .glow,
///             dockLabels: true, backdropBlur: 34, scrim: 0.38,
///             motion: .spring(response: 0.37, dampingFraction: 0.89))
/// ```
///
/// The layout choice lives in ``HarborLayout/Metrics`` (`frontScale`). The other choices are fixed
/// here rather than exposed as settings.
///
/// Opening runs in two beats, as Mission Control does: the desktop dims and the dock transforms
/// first (``backdropIn``), then the windows fly once the backdrop covers them (``backdropLead``).
/// Group cards, captions, and chips follow the flight with small delays. Closing reverses it: the
/// windows fly home at once, the chrome fades quickly, and the backdrop clears last so no real
/// window shows through while its thumbnail is still moving.
nonisolated enum HarborStyle {
    /// Blur radius of the wallpaper backdrop, in points.
    static let backdropBlur: CGFloat = 34
    /// Scrim drawn over the blurred wallpaper.
    static let scrimOpacity: Double = 0.38
    /// Scrim under Reduce Transparency, where the backdrop is not blurred.
    static let reducedTransparencyScrimOpacity: Double = 0.84
    /// The spring every window, group, and reflow uses.
    static let springResponse: Double = 0.37
    static let springDamping: Double = 0.89
    /// How much a hovered or selected window grows.
    static let hoverLift: CGFloat = 1.035
    /// Corner radius of a group card.
    static let groupCornerRadius: CGFloat = 24
    /// Corner radius of a window thumbnail at full size; it scales with the thumbnail.
    static let windowCornerRadius: CGFloat = 11
    /// The smallest corner radius a thumbnail is drawn with, so small thumbnails stay rounded.
    static let minimumThumbnailCornerRadius: CGFloat = 6
    /// Spectrum of the highlighted group's glow, matching the mockup.
    static let glowColors: [Color] = [
        Color(red: 1.0, green: 0.30, blue: 0.43), Color(red: 1.0, green: 0.62, blue: 0.26),
        Color(red: 1.0, green: 0.82, blue: 0.40), Color(red: 0.30, green: 0.79, blue: 0.94),
        Color(red: 0.26, green: 0.38, blue: 0.93), Color(red: 0.71, green: 0.09, blue: 0.62),
        Color(red: 1.0, green: 0.30, blue: 0.43),
    ]
    /// Seconds for one turn of the glow. Reduce Motion holds it still.
    static let glowPeriod: Double = 6
    /// How far the glow's soft halo reaches outside the card.
    static let glowReach: CGFloat = 18

    static var motion: Animation { .spring(response: springResponse, dampingFraction: springDamping) }
    static var hover: Animation { .spring(response: 0.28, dampingFraction: 0.78) }
    /// Crossfade used under Reduce Motion and for windows that have no thumbnail to fly.
    static var fade: Animation { .easeInOut(duration: 0.2) }

    // MARK: Opening and closing

    /// The backdrop covering the desktop. Ease-in-out keeps early thumbnails from popping over
    /// a desktop that has already dimmed.
    static var backdropIn: Animation { .easeInOut(duration: 0.24) }
    /// How long after the backdrop starts the windows may fly. Matches ``backdropIn`` so the
    /// desktop is covered before anything moves away from its real window.
    static let backdropLead: Duration = .milliseconds(240)
    /// The backdrop clearing on close, after the windows have mostly landed.
    static var backdropOut: Animation { .easeIn(duration: 0.24).delay(0.1) }
    /// Time from `leave` until the panels go: the spring has settled and the backdrop is clear.
    static let closeDuration: Duration = .milliseconds(390)
    /// Close under Reduce Motion, where everything crossfades together.
    static let reducedMotionCloseDuration: Duration = .milliseconds(240)

    /// Group cards settle in a beat after the windows start flying.
    static var cardIn: Animation { .easeOut(duration: 0.26).delay(0.07) }
    /// Captions follow the cards.
    static var captionIn: Animation { .easeOut(duration: 0.24).delay(0.16) }
    /// Chips come last.
    static var chipIn: Animation { .easeOut(duration: 0.24).delay(0.2) }
    /// The search field and notices drop in with a little overshoot.
    static var headerIn: Animation { .spring(response: 0.5, dampingFraction: 0.72) }
    /// Chrome leaving on close, ahead of the backdrop.
    static var chromeOut: Animation { .easeOut(duration: 0.15) }
    /// The dock becoming the strip, and back. Settles within ``closeDuration`` so the strip has
    /// landed on the real dock when the panels go.
    static var stripMorph: Animation { .spring(response: 0.42, dampingFraction: 0.86) }
    /// Window-count badges popping onto the strip.
    static var badgeIn: Animation { .spring(response: 0.36, dampingFraction: 0.58).delay(0.12) }
}
