import SwiftUI

/// Notification mark drawn on a dock app icon.
///
/// The count string stays on the app button for VoiceOver. This view only chooses the mark.
struct DockAppBadge: View {
    /// Red dot, or the numbered capsule.
    enum Style: Equatable, Sendable {
        /// Filled circle, smaller than the numbered capsule.
        case dot
        /// Numbered red capsule.
        case count
    }

    let label: String
    let iconSize: CGFloat
    var style: Style = .dot

    /// Smaller than the numbered capsule's minimum side (`iconSize * 0.32`).
    private var dotDiameter: CGFloat { iconSize * 0.22 }

    var body: some View {
        mark
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var mark: some View {
        switch style {
        case .dot:
            Circle()
                .fill(Color(nsColor: .systemRed))
                .overlay { Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1) }
                .frame(width: dotDiameter, height: dotDiameter)
        case .count:
            Text(verbatim: label)
                .font(.system(size: max(9, iconSize * 0.23), weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 4)
                .frame(minWidth: iconSize * 0.32, minHeight: iconSize * 0.32)
                .background(Color(nsColor: .systemRed), in: .capsule)
                .overlay { Capsule().strokeBorder(.white.opacity(0.85), lineWidth: 1) }
                .frame(maxWidth: iconSize * 0.85, alignment: .trailing)
        }
    }
}

#if DEBUG
#Preview("Dot and count") {
    HStack(alignment: .top, spacing: 20) {
        DockAppBadge(label: "3", iconSize: 32)
        DockAppBadge(label: "3", iconSize: 48)
        DockAppBadge(label: "3", iconSize: 80)
        DockAppBadge(label: "1", iconSize: 32, style: .count)
        DockAppBadge(label: "99+", iconSize: 56, style: .count)
        DockAppBadge(label: "!", iconSize: 80, style: .count)
        DockAppBadge(label: "Long badge text", iconSize: 56, style: .count)
    }.padding()
}

#Preview("Dot and count, dark") {
    HStack(alignment: .top, spacing: 20) {
        DockAppBadge(label: "3", iconSize: 48)
        DockAppBadge(label: "3", iconSize: 48, style: .count)
        DockAppBadge(label: "99+", iconSize: 56, style: .count)
    }
    .padding()
    .preferredColorScheme(.dark)
}
#endif
