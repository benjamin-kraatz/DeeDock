import SwiftUI

/// Instructions for getting the macOS Dock out of the way, with a live reading of whether it is.
///
/// Two routes: **Tuck Away macOS Dock** changes the Dock's preferences in one click through
/// `SystemDockTuckController`, and the System Settings link lets a person do it themselves.
/// DOKK writes the Dock's preferences only on that click. The status is phrased as *reserving
/// space*, which is what `SystemDockReservation` actually measures, so it confirms either route.
struct OnboardingSystemDockGuide: View {
    let reservesSpace: Bool
    /// Whether DOKK's values are in place; nil hides the one-click button.
    var isTucked: Bool? = nil
    var failure: LocalizedStringResource? = nil
    var openSettings: () -> Void = {}
    var tuckAway: () -> Void = {}
    var restore: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                instruction(number: 1, text: .onboardingSystemDockStepOne)
                instruction(number: 2, text: .onboardingSystemDockStepTwo)
            }
            HStack(spacing: 10) {
                if let isTucked { tuckButton(isTucked: isTucked) }
                Button(.onboardingOpenDesktopAndDock, action: openSettings)
            }
            status
            if let failure {
                Label { Text(failure) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func tuckButton(isTucked: Bool) -> some View {
        if isTucked {
            Button(.systemDockRestoreAction, systemImage: "arrow.uturn.backward", action: restore)
                .accessibilityHint(Text(.systemDockRestoreActionHint))
        } else {
            Button(.systemDockTuckAction, systemImage: "arrow.down.right.and.arrow.up.left", action: tuckAway)
                .buttonStyle(.borderedProminent)
                .tint(OnboardingStep.systemDock.tint)
                .accessibilityHint(Text(.systemDockTuckActionHint))
        }
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
                .contentTransition(.symbolEffect(.replace))
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
    OnboardingSystemDockGuide(reservesSpace: true, isTucked: false).padding(28).frame(width: 640)
}

#Preview("Guide — tucked away, dark") {
    OnboardingSystemDockGuide(reservesSpace: false, isTucked: true).padding(28).frame(width: 640)
        .preferredColorScheme(.dark)
}

#Preview("Guide — tuck failed") {
    OnboardingSystemDockGuide(reservesSpace: true, isTucked: false, failure: .systemDockTuckFailedWrite)
        .padding(28).frame(width: 640)
}

#Preview("Guide — without the switch") {
    OnboardingSystemDockGuide(reservesSpace: false).padding(28).frame(width: 640)
}

#Preview("Guide — large text") {
    OnboardingSystemDockGuide(reservesSpace: true, isTucked: false).padding(28).frame(width: 460)
        .dynamicTypeSize(.accessibility1)
}
#endif
