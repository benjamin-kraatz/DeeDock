import SwiftUI

/// Instructions for getting the macOS Dock out of the way, with a live reading of whether it is.
///
/// DeeDock never writes the system Dock's preferences, so this asks rather than acts: it opens
/// the right pane and then reports what it can observe. The status is phrased as *reserving
/// space*, which is what `SystemDockReservation` actually measures — not as the state of a
/// switch DeeDock cannot see.
struct OnboardingSystemDockGuide: View {
    let reservesSpace: Bool
    var openSettings: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                instruction(number: 1, text: .onboardingSystemDockStepOne)
                instruction(number: 2, text: .onboardingSystemDockStepTwo)
            }
            HStack(spacing: 14) {
                Button(.onboardingOpenDesktopAndDock, action: openSettings)
                status
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func instruction(number: Int, text: LocalizedStringResource) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(number.formatted())
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(Circle().fill(OnboardingStep.systemDock.tint))
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One live element rather than two, so VoiceOver announces the change instead of a
    /// checkmark appearing and a sentence disappearing independently.
    private var status: some View {
        HStack(spacing: 6) {
            Image(systemName: reservesSpace ? "circle.dotted" : "checkmark.circle.fill")
                .foregroundStyle(reservesSpace ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.green))
                .accessibilityHidden(true)
            Text(reservesSpace ? .onboardingSystemDockStatusReserving : .onboardingSystemDockStatusClear)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: reservesSpace)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#if DEBUG
#Preview("Guide — Dock still reserving space") {
    OnboardingSystemDockGuide(reservesSpace: true).padding(28).frame(width: 640)
}

#Preview("Guide — space released, dark") {
    OnboardingSystemDockGuide(reservesSpace: false).padding(28).frame(width: 640)
        .preferredColorScheme(.dark)
}

#Preview("Guide — large text") {
    OnboardingSystemDockGuide(reservesSpace: true).padding(28).frame(width: 460)
        .dynamicTypeSize(.accessibility1)
}
#endif
