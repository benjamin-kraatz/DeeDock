import SwiftUI

/// A static outline and badge identify the display being edited without covering its content.
struct DisplaySelectionIndicatorView: View {
    let displayName: String
    /// Distance from the physical screen top to a position below reserved menu-bar/notch space.
    var badgeTopInset: CGFloat = 44
    /// Explicit appearance for inert previews; live presentation follows the system environment.
    var reduceTransparency: Bool? = nil
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.accentColor, lineWidth: 4)
                .padding(8)
            HStack(spacing: 10) {
                Image(systemName: "display")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(.displayIndicatorEditing)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(verbatim: displayName)
                        .font(.headline)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: 360)
            .background {
                if reduceTransparency ?? systemReduceTransparency {
                    RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    RoundedRectangle(cornerRadius: 16).fill(.regularMaterial)
                }
            }
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.tint, lineWidth: 1) }
            .padding(.horizontal, 24)
            .padding(.top, badgeTopInset)
        }
        // Settings already exposes the selected profile. This purely visual marker must not add
        // another focus target, and stays static regardless of the Reduce Motion preference.
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview("Selected display") {
    DisplaySelectionIndicatorView(displayName: "Studio Display")
        .frame(width: 800, height: 480)
}

#Preview("Long display name, dark and reduced transparency") {
    DisplaySelectionIndicatorView(displayName: "External display — Design workspace", reduceTransparency: true)
        .preferredColorScheme(.dark)
        .frame(width: 800, height: 480)
}
#endif
