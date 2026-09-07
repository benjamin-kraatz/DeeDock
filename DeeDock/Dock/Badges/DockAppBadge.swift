import SwiftUI

/// Upright badge text stays inside the icon bounds on every Dock edge and magnification size.
struct DockAppBadge: View {
    let label: String
    let iconSize: CGFloat

    var body: some View {
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
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Badge text and sizes") {
    HStack(alignment: .top, spacing: 20) {
        DockAppBadge(label: "1", iconSize: 32)
        DockAppBadge(label: "99+", iconSize: 56)
        DockAppBadge(label: "!", iconSize: 80)
        DockAppBadge(label: "Long badge text", iconSize: 56)
    }.padding()
}
#endif
