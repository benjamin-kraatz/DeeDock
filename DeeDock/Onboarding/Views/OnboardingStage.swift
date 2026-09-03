import SwiftUI

/// The fixed hero area at the top of every tour page.
///
/// Stages are decorative demonstrations of the product, so the container hides them from
/// assistive technology; the step's title and summary carry the meaning. The height is fixed so
/// that moving between steps never resizes the window or shifts the copy underneath.
struct OnboardingStage<Content: View>: View {
    var tint: Color
    /// Previews pass an explicit value; the stage otherwise follows the system setting.
    var reduceTransparencyOverride: Bool? = nil
    // Last, so callers can supply the stage's content as a trailing closure.
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    /// Tall enough for a full screen diagram at its natural scale, short enough to leave the
    /// copy and controls comfortably above the window's bottom edge.
    static var height: CGFloat { 288 }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: Self.height)
            .background {
                // A faint wash of the step's identity color under a neutral surface, so the
                // stage reads as a lit alcove rather than a colored panel.
                shape.fill(.background)
                shape.fill(LinearGradient(colors: [tint.opacity(reduceTransparency ? 0.10 : 0.16), tint.opacity(0.02)],
                                          startPoint: .top, endPoint: .bottom))
            }
            .overlay { shape.strokeBorder(tint.opacity(0.18), lineWidth: 0.5) }
            .clipShape(shape)
            .accessibilityHidden(true)
    }
}
