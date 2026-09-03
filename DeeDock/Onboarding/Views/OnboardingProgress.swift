import SwiftUI

/// Page dots for the tour.
///
/// The row is one accessibility element reading "Step 3 of 7"; seven anonymous circles would
/// be noise in the rotor without telling anyone where they are.
struct OnboardingProgress: View {
    let step: OnboardingStep
    let total: Int
    var tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases) { candidate in
                let isCurrent = candidate == step
                Capsule(style: .continuous)
                    .fill(isCurrent ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
                    // The current step widens rather than brightening alone, so the position
                    // stays readable without relying on color.
                    .frame(width: isCurrent ? 18 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.onboardingProgress(step: step.index + 1, total: total)))
    }
}

#if DEBUG
#Preview("Progress") {
    VStack(spacing: 14) {
        ForEach(OnboardingStep.allCases) { step in
            OnboardingProgress(step: step, total: OnboardingStep.allCases.count, tint: step.tint)
        }
    }.padding()
}
#endif
