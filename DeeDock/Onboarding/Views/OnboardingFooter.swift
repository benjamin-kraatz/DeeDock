import SwiftUI

/// The tour's navigation row: progress on the left, actions on the right.
///
/// Value-driven, so previews and tests never need a store or a window.
struct OnboardingFooter: View {
    let step: OnboardingStep
    let total: Int
    let canGoBack: Bool
    let isFinalStep: Bool
    var back: () -> Void = {}
    var skip: () -> Void = {}
    var advance: () -> Void = {}
    var openSettings: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            OnboardingProgress(step: step, total: total, tint: step.tint)
            Spacer(minLength: 12)
            if step.isSkippable {
                Button(.onboardingSkip, action: skip)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            if isFinalStep {
                Button(.onboardingOpenSettings, action: openSettings)
            }
            if canGoBack {
                Button(.onboardingBack, action: back)
            }
            Button(isFinalStep ? .onboardingFinish : .onboardingContinue, action: advance)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .tint(step.tint)
    }
}

#if DEBUG
#Preview("Footer states") {
    VStack(spacing: 22) {
        OnboardingFooter(step: .welcome, total: 7, canGoBack: false, isFinalStep: false)
        OnboardingFooter(step: .systemDock, total: 7, canGoBack: true, isFinalStep: false)
        OnboardingFooter(step: .ready, total: 7, canGoBack: true, isFinalStep: true)
    }
    .padding(24)
    .frame(width: 640)
}

#Preview("Footer — large text") {
    OnboardingFooter(step: .ready, total: 7, canGoBack: true, isFinalStep: true)
        .padding(24).frame(width: 640)
        .dynamicTypeSize(.accessibility1)
}
#endif
