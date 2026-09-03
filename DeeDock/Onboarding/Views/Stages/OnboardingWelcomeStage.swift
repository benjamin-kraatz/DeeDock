import SwiftUI

/// A dock magnifying under an unhurried pointer sweep.
///
/// This is the real layout engine, not an illustration: `DockGeometry.layout` produces the
/// frames and `DockSampleView` draws them, so what a person sees here is what they will get.
struct OnboardingWelcomeStage: View {
    /// Previews and the surrounding tour can pass an explicit value; the stage otherwise
    /// follows the system setting, matching `DockSampleView`.
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    /// Pointer position as a fraction of the canvas, so the loop is independent of layout size.
    @State private var fraction: CGFloat = 0.12

    private static let sweep = (start: CGFloat(0.12), end: CGFloat(0.88))

    private var layout: DockGeometry.Layout {
        DockGeometry.layout(count: 7, favoriteCount: 4, availableLength: 620,
                            settings: DockSettings(iconSize: 52, magnification: 1.55, itemSpacing: 6))
    }

    var body: some View {
        let layout = layout
        MagnifiedDockSample(layout: layout, fraction: reduceMotion ? 0.5 : fraction)
            .frame(width: layout.viewportSize.width, height: layout.viewportSize.height)
            .task(id: reduceMotion) { await sweepContinuously() }
    }

    /// One task for as long as the step is on screen; SwiftUI cancels it on the way out, so a
    /// step a person has left animates nothing. Reduce Motion holds a single resting frame.
    private func sweepContinuously() async {
        guard !reduceMotion else { return }
        var target = Self.sweep.end
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 2.8)) { fraction = target }
            try? await Task.sleep(for: .seconds(3.1))
            target = target == Self.sweep.end ? Self.sweep.start : Self.sweep.end
        }
    }
}

/// Re-renders the sample once per frame of a sweep.
///
/// `DockSampleView` recomputes its icon sizes from a pointer position, which SwiftUI would
/// otherwise snap between values. Conforming the wrapper to `Animatable` — the same technique
/// `DockBackgroundView` uses — makes SwiftUI interpolate the position and call `body` for each
/// intermediate value, producing the continuous magnification the real dock shows.
private struct MagnifiedDockSample: View, Animatable {
    let layout: DockGeometry.Layout
    var fraction: CGFloat

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        DockSampleView(layout: layout, pointerAlong: layout.canvasLength * fraction)
    }
}

#if DEBUG
#Preview("Welcome stage") {
    OnboardingStage(tint: OnboardingStep.welcome.tint) { OnboardingWelcomeStage() }
        .padding(28).frame(width: 700)
}

#Preview("Welcome stage — Reduce Motion") {
    OnboardingStage(tint: OnboardingStep.welcome.tint) {
        OnboardingWelcomeStage(reduceMotionOverride: true)
    }
    .padding(28).frame(width: 700)
}
#endif
