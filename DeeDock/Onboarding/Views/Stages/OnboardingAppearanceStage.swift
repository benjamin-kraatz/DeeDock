import SwiftUI

/// A magnified dock changing its running indicators, all icons agreeing.
///
/// The whole dock cross-fades between styles rather than showing several at once. A dock whose
/// apps each wore a different marker would be a showroom, not a dock: it is not a state anyone's
/// screen can reach, and the page is meant to show what theirs will look like.
///
/// Indicators are drawn by `DockSampleView`, which applies both halves of a style — the icon
/// treatment from `DockIconIndicator` and the separate mark from `DockRunningIndicator` — so the
/// expressive styles appear here exactly as they do on a real dock.
struct OnboardingAppearanceStage: View {
    /// Previews and the surrounding tour can pass an explicit value; the stage otherwise
    /// follows the system setting, matching `DockSampleView`.
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    @State private var index = 0

    /// A spread across the gallery — the restrained default, two geometric marks, and three of
    /// the expressive ones — rather than all fifteen, which at this pace would be a flicker.
    private static let styles: [DockSettings.RunningIndicatorStyle] = [.dot, .bar, .neon, .aura, .orbit, .prism]

    private var style: DockSettings.RunningIndicatorStyle { Self.styles[index % Self.styles.count] }

    private var layout: DockGeometry.Layout {
        DockGeometry.layout(count: 6, favoriteCount: 6, availableLength: 560,
                            settings: DockSettings(iconSize: 58, magnification: 1.4, itemSpacing: 8))
    }

    var body: some View {
        let layout = layout
        DockSampleView(layout: layout, magnified: true, runningIndicatorStyle: style)
            .frame(width: layout.viewportSize.width, height: layout.viewportSize.height)
            .id(index)
            // The two frames differ only in their markers, so a cross-fade of the whole dock
            // reads as the markers changing rather than as the dock being replaced.
            .transition(.opacity)
            .task(id: reduceMotion) { await cycle() }
    }

    private func cycle() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2.1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) { index += 1 }
        }
    }
}

#if DEBUG
#Preview("Appearance stage") {
    OnboardingStage(tint: OnboardingStep.appearance.tint) { OnboardingAppearanceStage() }
        .padding(28).frame(width: 700)
}

#Preview("Appearance stage — Reduce Motion") {
    OnboardingStage(tint: OnboardingStep.appearance.tint) {
        OnboardingAppearanceStage(reduceMotionOverride: true)
    }
    .padding(28).frame(width: 700)
}
#endif
