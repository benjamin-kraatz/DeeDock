import SwiftUI

/// The number-row digit drawn on an application icon's leading corner while Quick Launch hints show.
///
/// Decorative only: it never takes clicks, and VoiceOver hears the shortcut through the icon's
/// own custom content instead. It sits opposite the badge corner so both can show at once.
struct QuickLaunchNumberChip: View {
    let label: String
    /// Current icon dimension; the chip scales with magnification so it stays attached to the artwork.
    let iconSize: CGFloat
    /// Emphasises the item a shortcut just opened.
    var highlighted = false
    /// Uses an opaque fill instead of glass, for Reduce Transparency.
    var opaque = false

    private var diameter: CGFloat { max(15, iconSize * 0.36) }

    var body: some View {
        Text(verbatim: label)
            .font(.system(size: diameter * 0.62, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .frame(minWidth: diameter, minHeight: diameter)
            .background { background }
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    @ViewBuilder private var background: some View {
        if highlighted {
            Capsule().fill(Color.accentColor)
        } else if opaque {
            Capsule().fill(Color(nsColor: .windowBackgroundColor))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
        } else {
            Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
        }
    }
}

#if DEBUG
#Preview("Quick Launch chips") {
    HStack(spacing: 18) {
        ForEach(["1", "2", "0"], id: \.self) { label in
            RoundedRectangle(cornerRadius: 11).fill(.blue.gradient).frame(width: 48, height: 48)
                .overlay(alignment: .topLeading) { QuickLaunchNumberChip(label: label, iconSize: 48).offset(x: -4, y: -4) }
        }
        RoundedRectangle(cornerRadius: 11).fill(.orange.gradient).frame(width: 48, height: 48)
            .overlay(alignment: .topLeading) {
                QuickLaunchNumberChip(label: "4", iconSize: 48, highlighted: true).offset(x: -4, y: -4)
            }
        RoundedRectangle(cornerRadius: 16).fill(.green.gradient).frame(width: 72, height: 72)
            .overlay(alignment: .topLeading) { QuickLaunchNumberChip(label: "5", iconSize: 72).offset(x: -4, y: -4) }
    }
    .padding(32)
}

#Preview("Quick Launch chips, opaque, dark") {
    HStack(spacing: 18) {
        ForEach(["1", "2", "3"], id: \.self) { label in
            RoundedRectangle(cornerRadius: 11).fill(.purple.gradient).frame(width: 48, height: 48)
                .overlay(alignment: .topLeading) {
                    QuickLaunchNumberChip(label: label, iconSize: 48, opaque: true).offset(x: -4, y: -4)
                }
        }
    }
    .padding(32)
    .preferredColorScheme(.dark)
}
#endif
