import SwiftUI

/// A hidden dock revealing itself when the pointer reaches its activation zone.
///
/// Driven by the production `DockVisibilityController` and `DockAnimationGeometry`, so the
/// timing and the motion are the ones auto-hide actually performs — not a re-creation of them.
struct OnboardingHidingStage: View {
    /// Previews and the surrounding tour can pass an explicit value; the stage otherwise
    /// follows the system setting, matching `DockSampleView`.
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    @State private var controller = DockVisibilityController()
    /// How far the pointer has travelled into the activation zone, 0 away and 1 inside.
    @State private var approach: Double = 0

    private static let animationDuration = 0.28
    private static let zoneHeight: CGFloat = 10
    private static let travel: CGFloat = 74

    private var layout: DockGeometry.Layout {
        DockGeometry.layout(count: 5, favoriteCount: 5, availableLength: 380,
                            settings: DockSettings(iconSize: 42, magnification: 1, itemSpacing: 6))
    }

    var body: some View {
        let layout = layout
        let size = layout.viewportSize
        VStack(spacing: 10) {
            DockSampleView(layout: layout)
                .frame(width: size.width, height: size.height)
                .modifier(DockPresentationModifier(
                    sample: DockAnimationGeometry.sample(style: .slideFade, progress: controller.progress,
                                                        size: size, reduceMotion: reduceMotion, edge: .bottom),
                    size: size))
                .frame(width: size.width, height: size.height)
                .clipped()
                .overlay(alignment: .top) { pointer }
            activationZone(width: size.width)
        }
        .task(id: reduceMotion) { await cycle() }
        .onDisappear { controller.stop() }
    }

    /// The strip a pointer has to reach, in the same cyan the Behavior pane's zone diagram uses.
    private func activationZone(width: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(.cyan.opacity(0.25 + 0.55 * approach))
            .frame(width: width * 0.7, height: Self.zoneHeight)
            .overlay { Capsule(style: .continuous).strokeBorder(.cyan.opacity(0.7), lineWidth: 0.5) }
    }

    /// A pointer standing in for the person's own, so the cause of the reveal is visible.
    private var pointer: some View {
        Circle()
            .fill(.white)
            .frame(width: 9, height: 9)
            .overlay { Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .offset(y: Self.travel * approach)
            .opacity(0.9)
    }

    /// Approach, reveal, linger, withdraw, hide — the loop a person performs without noticing.
    /// Reduce Motion settles on the revealed state and starts nothing.
    private func cycle() async {
        var settings = DockBehaviorSettings()
        settings.autoHide = true
        settings.revealDelay = 0
        settings.hideDelay = 0
        settings.animationStyle = .slideFade
        settings.animationDuration = Self.animationDuration
        controller.configure(settings, reduceMotion: reduceMotion)

        guard !reduceMotion else {
            approach = 1
            controller.update(activation: false, retained: false, held: true)
            return
        }

        while !Task.isCancelled {
            controller.update(activation: false, retained: false, held: false)
            withAnimation(.easeInOut(duration: 0.45)) { approach = 0 }
            try? await Task.sleep(for: .seconds(1.3))
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.55)) { approach = 1 }
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }

            controller.update(activation: false, retained: false, held: true)
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
        }
    }
}

#if DEBUG
#Preview("Hiding stage") {
    OnboardingStage(tint: OnboardingStep.hiding.tint) { OnboardingHidingStage() }
        .padding(28).frame(width: 700)
}

#Preview("Hiding stage — Reduce Motion") {
    OnboardingStage(tint: OnboardingStep.hiding.tint) {
        OnboardingHidingStage(reduceMotionOverride: true)
    }
    .padding(28).frame(width: 700)
}
#endif
