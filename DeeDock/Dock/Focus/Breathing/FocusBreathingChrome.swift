import SwiftUI

/// Decorative highlight confined to the existing background bounds, below every dock item.
/// Removing the timeline stops frame scheduling immediately for hidden or reduced-motion docks.
struct FocusBreathingChrome: View {
    let active: Bool
    let intensity: Double
    let reduceMotion: Bool
    let cornerRadius: CGFloat
    let backgroundOpacity: Double

    var body: some View {
        if active && !reduceMotion && intensity > 0 && backgroundOpacity > 0 {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                // One shared clock keeps all displays in phase. Only the highlight is redrawn.
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6
                let breath = (1 - cos(phase * 2 * .pi)) / 2
                let amount = min(100, max(0, intensity)) / 100
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.tint.opacity(amount * (0.015 + 0.075 * breath)))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(.tint.opacity(amount * (0.06 + 0.24 * breath)), lineWidth: 1)
                    }
                    .opacity(backgroundOpacity)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transaction { $0.animation = nil }
        }
    }
}

#if DEBUG
#Preview("Breathing chrome") {
    ZStack {
        DockBackgroundView(reduceTransparency: false)
        FocusBreathingChrome(active: true, intensity: 30, reduceMotion: false,
                             cornerRadius: 22, backgroundOpacity: 1)
    }
    .frame(width: 320, height: 70).padding(24)
}

#Preview("Reduce Motion and opaque background") {
    ZStack {
        DockBackgroundView(reduceTransparency: true)
        FocusBreathingChrome(active: true, intensity: 100, reduceMotion: true,
                             cornerRadius: 22, backgroundOpacity: 1)
    }
    .frame(width: 320, height: 70).padding(24)
}
#endif
