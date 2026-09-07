import SwiftUI

/// Fades driven by the morph's own interpolated progress rather than by a parallel animation.
///
/// `Animatable` hands these modifiers the spring's value on every frame, so the contents resolve
/// against the glass's actual travel. A fade on its own timeline reads as two states swapping;
/// tied to the shape, it reads as the shape carrying them.
///
/// Phase is 0 at the dock's rect and 1 at the expanded rect, and passes 1 while the spring settles.

/// The dock's contents dissolve into the glass as it leaves their rect, growing very slightly so
/// they read as being absorbed by the expansion rather than dimming in place.
struct DockMorphFade: ViewModifier, Animatable {
    var phase: Double
    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func body(content: Content) -> some View {
        let progress = min(1, max(0, phase) / 0.35)
        content
            .scaleEffect(1 + 0.04 * progress)
            .blur(radius: 5 * progress)
            .opacity(1 - progress)
    }
}

/// The launcher's contents resolve over the back half of the same travel, so they arrive as the
/// glass reaches its expanded rect.
struct LauncherMorphFade: ViewModifier, Animatable {
    var phase: Double
    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func body(content: Content) -> some View {
        let progress = min(1, max(0, (min(phase, 1) - 0.4) / 0.5))
        content
            .blur(radius: 5 * (1 - progress))
            .opacity(progress)
    }
}
