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
    /// How far through the current style's dwell the cycle has travelled, 0 to 1.
    @State private var elapsed: Double = 0

    /// A spread across the gallery — the restrained default, two geometric marks, and three of
    /// the expressive ones — rather than all fifteen, which at this pace would be a flicker.
    private static let styles: [DockSettings.RunningIndicatorStyle] = [.dot, .bar, .stardust, .orbit, .prism, .singularity]
    private static let dwell: Double = 1.5
    private static let crossFade: Double = 0.4

    private var style: DockSettings.RunningIndicatorStyle { Self.styles[index % Self.styles.count] }

    private var layout: DockGeometry.Layout {
        DockGeometry.layout(count: 6, favoriteCount: 6, availableLength: 560,
                            settings: DockSettings(iconSize: 58, magnification: 1.4, itemSpacing: 8))
    }

    var body: some View {
        let layout = layout
        VStack(spacing: 16) {
            DockSampleView(layout: layout, magnified: true, runningIndicatorStyle: style)
                .frame(width: layout.viewportSize.width, height: layout.viewportSize.height)
                .id(index)
                // The two frames differ only in their markers, so a cross-fade of the whole dock
                // reads as the markers changing rather than as the dock being replaced.
                .transition(.opacity)
            caption(width: layout.viewportSize.width * 0.62)
        }
        .task(id: reduceMotion) { await cycle() }
    }

    /// Names the marker on screen and shows how long it stays.
    ///
    /// Without this the dock changes for no visible reason and a person is left waiting to find
    /// out whether it will change again. The name also teaches the vocabulary they will meet in
    /// Settings. Under Reduce Motion nothing is running, so only the name is shown.
    private func caption(width: CGFloat) -> some View {
        HStack(spacing: 12) {
            Text(style.indicatorName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .animation(nil, value: index)
                .frame(width: 90, alignment: .leading)
            if !reduceMotion {
                Capsule(style: .continuous)
                    .fill(.quaternary)
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule(style: .continuous)
                                .fill(.secondary)
                                .frame(width: proxy.size.width * elapsed)
                        }
                    }
            }
        }
        .frame(width: width)
        .accessibilityHidden(true)
    }

    private func cycle() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            // Reset without animation, then let the fill run the length of the dwell, so the bar
            // reads as time remaining rather than as an unexplained decoration.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { elapsed = 0 }
            withAnimation(.linear(duration: Self.dwell)) { elapsed = 1 }

            try? await Task.sleep(for: .seconds(Self.dwell))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: Self.crossFade)) { index += 1 }
        }
    }
}

private extension DockSettings.RunningIndicatorStyle {
    /// The name Settings gives this style, rather than a second set of strings that could drift.
    var indicatorName: LocalizedStringResource {
        Self.settingsOptions.first { $0.value == self }?.title ?? .settingsIndicatorDot
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
