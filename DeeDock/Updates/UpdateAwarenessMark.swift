#if DIRECT_DISTRIBUTION
import SwiftUI

/// Soft indigo-to-coral mark used by the menu-bar badge, Settings badge, and dock pip.
enum UpdateAwarenessMark {
    static let indigo = Color(red: 0.45, green: 0.42, blue: 0.92)
    static let coral = Color(red: 0.96, green: 0.48, blue: 0.42)

    static var fill: LinearGradient {
        LinearGradient(colors: [indigo, coral], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Compact badge for the menu bar extra and Settings tiles.
struct UpdateAwarenessBadge: View {
    var diameter: CGFloat = 8

    var body: some View {
        Circle()
            .fill(UpdateAwarenessMark.fill)
            .overlay { Circle().strokeBorder(.white.opacity(0.88), lineWidth: 0.8) }
            .frame(width: diameter, height: diameter)
            .accessibilityLabel(Text(.updatesAwarenessBadge))
    }
}

/// Dock-adjacent pip on DDock glass. Reduce Motion keeps it static.
struct UpdateAwarenessPip: View {
    let reduceMotion: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(UpdateAwarenessMark.fill)
            .overlay { Circle().strokeBorder(.white.opacity(0.55), lineWidth: 0.7) }
            .frame(width: 9, height: 9)
            .shadow(color: UpdateAwarenessMark.indigo.opacity(0.35), radius: reduceMotion ? 0 : 3)
            .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.72))
            .animation(reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                       value: pulse)
            .onAppear { pulse = !reduceMotion }
            .accessibilityLabel(Text(.updatesAwarenessPip))
    }
}

#Preview("Marks") {
    HStack(spacing: 20) {
        UpdateAwarenessBadge()
        UpdateAwarenessPip(reduceMotion: true)
        UpdateAwarenessPip(reduceMotion: false)
    }
    .padding(24)
}
#endif
