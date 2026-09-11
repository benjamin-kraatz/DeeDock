import SwiftUI

extension Color {
    /// The stamp's lacquered red, sampled from the glyph so tints and accents read as its ink.
    static let quarantineStamp = Color(red: 0.78, green: 0.27, blue: 0.16)
}

/// The stamp illustration beside the feature switch. Off, the stamp hovers tilted and grey over
/// clean paper; switching on presses it down once and leaves an ink mark behind.
struct QuarantineStampHero: View {
    let active: Bool
    /// Previews pass a value to show the still path; nil follows the system setting.
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        ZStack {
            Image("QuarantineInk")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-14))
                .offset(x: 12, y: 18)
                .scaleEffect(active ? 1 : 0.3)
                .opacity(active ? 0.85 : 0)
                // The mark lands after the press bottoms out, not with the switch.
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.3).delay(0.14),
                           value: active)
            Image("QuarantineGlyph")
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
                .rotationEffect(.degrees(active || reduceMotion ? 0 : -16), anchor: .bottom)
                .offset(y: active || reduceMotion ? -2 : -8)
                .saturation(active ? 1 : 0)
                .opacity(active ? 1 : 0.55)
                .keyframeAnimator(initialValue: 1.0, trigger: active) { content, squash in
                    content.scaleEffect(x: 2 - squash, y: squash, anchor: .bottom)
                } keyframes: { _ in
                    if active && !reduceMotion {
                        CubicKeyframe(1.06, duration: 0.1)
                        CubicKeyframe(0.84, duration: 0.07)
                        SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
                    } else {
                        LinearKeyframe(1.0, duration: 0.01)
                    }
                }
                .animation(.spring(duration: 0.3, bounce: 0.2), value: active)
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Hero stamp") {
    @Previewable @State var active = false
    VStack(spacing: 16) {
        HStack(spacing: 24) {
            QuarantineStampHero(active: active)
            QuarantineStampHero(active: active, reduceMotionOverride: true)
        }
        Toggle("Active", isOn: $active).toggleStyle(.switch)
    }
    .padding(32)
}
#endif
