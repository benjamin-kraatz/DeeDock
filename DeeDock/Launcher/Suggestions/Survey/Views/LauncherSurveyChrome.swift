import SwiftUI

/// The card's surface: a faint accent wash with a glow in the badge corner, a hairline edge,
/// and a light that travels once around the edge whenever `pulse` changes.
///
/// The sweep is a keyframe animation with a trigger, so it renders only while it runs; an idle
/// card costs nothing per frame. Reduce Motion leaves the edge static; Reduce Transparency
/// replaces the wash with an opaque fill.
struct LauncherSurveyCardBackground: View {
    let pulse: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        // The keyframe content closure is not main-actor isolated, so it gets plain values.
        let shape = Self.shape
        let sweepVisibility = reduceMotion ? 0.0 : 1.0
        return shape
            .fill(reduceTransparency ? AnyShapeStyle(.background.secondary) : AnyShapeStyle(.tint.opacity(0.07)))
            .overlay(alignment: .topLeading) {
                if !reduceTransparency {
                    RadialGradient(colors: [.accentColor.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 140)
                        .frame(width: 280, height: 220)
                        .offset(x: -110, y: -110)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(.white.opacity(0.09)) }
            .keyframeAnimator(initialValue: Sweep(), trigger: pulse) { content, sweep in
                content.overlay {
                    shape.strokeBorder(
                        AngularGradient(colors: [.clear, .accentColor, .purple.opacity(0.8), .clear, .clear],
                                        center: .center, angle: sweep.angle),
                        lineWidth: 1.5)
                    .opacity(sweepVisibility * sweep.opacity)
                }
            } keyframes: { _ in
                KeyframeTrack(\.angle) {
                    LinearKeyframe(.degrees(0), duration: 0)
                    CubicKeyframe(.degrees(360), duration: 1.6)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.25)
                    LinearKeyframe(1, duration: 1.0)
                    LinearKeyframe(0, duration: 0.35)
                }
            }
    }

    private struct Sweep {
        var angle = Angle.zero
        var opacity = 0.0
    }
}

/// The round gradient badge at the card's leading edge. Its symbol morphs between states.
struct LauncherSurveyBadge: View {
    let symbol: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
            .frame(width: 30, height: 30)
            .background {
                Circle().fill(LinearGradient(colors: [.accentColor, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .shadow(color: .accentColor.opacity(0.4), radius: 6, y: 2)
            .accessibilityHidden(true)
    }
}

/// One capsule per question still possible. Answered ones are filled, the current one is
/// stretched, and the row shrinks when branching skips ahead.
struct LauncherSurveyProgress: View {
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= completed ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary))
                    .opacity(index < completed ? 0.55 : 1)
                    .frame(width: index == completed ? 16 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(.launcherSurveyProgress(completed + 1, total)))
    }
}
