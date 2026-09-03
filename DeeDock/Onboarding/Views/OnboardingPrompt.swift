import SwiftUI

/// One line under a stage a person can actually operate.
///
/// This is the whole of the tour's interaction vocabulary: a stage with a prompt beneath it
/// changes something when clicked, and a stage without one is a demonstration that runs itself.
/// Never attach a prompt to a page that only animates — the contrast is what makes it readable.
struct OnboardingPrompt: View {
    let text: LocalizedStringResource
    var tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Prompt") {
    OnboardingPrompt(text: .onboardingPlacementPrompt, tint: OnboardingStep.placement.tint)
        .padding(24)
}
#endif
