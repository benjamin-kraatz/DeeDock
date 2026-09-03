import SwiftUI

/// Two desktops, each with its own dock, taking the selection in turn.
///
/// The differing edges and alignments are the point: displays share defaults but override any
/// control independently, and both diagrams run the same placement calculation to prove it.
struct OnboardingDisplaysStage: View {
    /// Previews and the surrounding tour can pass an explicit value; the stage otherwise
    /// follows the system setting, matching `DockSampleView`.
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    @State private var selected = 0

    private static let arrangements: [DockSettings] = [
        DockSettings(iconSize: 40, edge: .bottom, alignment: .center, edgeDistance: 10),
        DockSettings(iconSize: 40, edge: .left, alignment: .start, alongEdgeOffset: 40, edgeDistance: 14)
    ]

    var body: some View {
        HStack(spacing: 18) {
            ForEach(Self.arrangements.indices, id: \.self) { index in
                DockDisplayDiagram(settings: Self.arrangements[index], showsActivation: false)
                    .fixedSize()
                    .overlay {
                        // The marker matches the outline Settings draws on a real display when
                        // that display is selected, so the idea carries over to the window.
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.tint, lineWidth: 2.5)
                            .opacity(selected == index ? 1 : 0)
                    }
                    .scaleEffect(selected == index ? 1 : 0.94)
                    .opacity(selected == index ? 1 : 0.62)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: selected)
        .tint(OnboardingStep.displays.tint)
        .task(id: reduceMotion) { await alternate() }
    }

    private func alternate() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2.1))
            guard !Task.isCancelled else { return }
            selected = (selected + 1) % Self.arrangements.count
        }
    }
}

#if DEBUG
#Preview("Displays stage") {
    OnboardingStage(tint: OnboardingStep.displays.tint) { OnboardingDisplaysStage() }
        .padding(28).frame(width: 700)
}
#endif
