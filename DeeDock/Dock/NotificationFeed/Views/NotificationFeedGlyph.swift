import SwiftUI

/// The notification feed's tile artwork: a brass bell that rings when something arrives.
///
/// Drawn from the `bell.fill` symbol so it scales cleanly at every dock size. `ring` is a counter;
/// each increment plays one short swing about the bell's crown. Reduce Motion skips the swing.
struct NotificationFeedGlyph: View {
    var size: CGFloat
    var ring = 0
    var reduceMotion = false
    /// Drop shadows help on the dock but muddy the mark inline in a panel header.
    var elevated = true

    private var bellGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 1.0, green: 0.86, blue: 0.42),
                                Color(red: 0.96, green: 0.66, blue: 0.16),
                                Color(red: 0.78, green: 0.46, blue: 0.08)],
                       startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        Image(systemName: "bell.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(bellGradient)
            .overlay {
                // A soft specular sweep across the shoulder of the bell.
                Image(systemName: "bell.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(LinearGradient(colors: [.white.opacity(0.55), .clear],
                                                    startPoint: .topLeading, endPoint: .center))
                    .blendMode(.plusLighter)
            }
            .frame(width: size * 0.66, height: size * 0.66)
            .shadow(color: .black.opacity(elevated ? 0.28 : 0), radius: size * 0.05, y: size * 0.03)
            .keyframeAnimator(initialValue: 0.0, trigger: ring) { content, angle in
                content.rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.5, y: 0.12))
            } keyframes: { _ in
                if reduceMotion {
                    LinearKeyframe(0, duration: 0.01)
                } else {
                    CubicKeyframe(16, duration: 0.09)
                    CubicKeyframe(-13, duration: 0.14)
                    CubicKeyframe(9, duration: 0.12)
                    CubicKeyframe(-5, duration: 0.1)
                    SpringKeyframe(0, duration: 0.3, spring: .bouncy)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Bell sizes") {
    HStack(spacing: 24) {
        NotificationFeedGlyph(size: 32)
        NotificationFeedGlyph(size: 56)
        NotificationFeedGlyph(size: 96)
    }
    .padding(32)
}

#Preview("Bell, dark") {
    NotificationFeedGlyph(size: 72)
        .padding(32)
        .preferredColorScheme(.dark)
}
#endif
