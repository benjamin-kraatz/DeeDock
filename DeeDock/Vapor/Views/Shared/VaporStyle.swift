import SwiftUI

/// Colours shared by the panel, capsules and bubbles. They follow the mockup's tokens and use
/// semantic colours where the system has one, so light and dark both work.
enum VaporStyle {
    /// Chip and secondary-button fill.
    static let chip = Color.primary.opacity(0.07)
    /// Hairlines between sections.
    static let line = Color.primary.opacity(0.08)
    /// Edges of capsules, cards and the dashed drop zone.
    static let line2 = Color.primary.opacity(0.15)
    /// A hovered row.
    static let selection = Color.primary.opacity(0.06)
    /// The accent's light fill (Undo, the targeted drop zone).
    static let accentSoft = Color.accentColor.opacity(0.18)
    /// The delete button and the remove-hover fill.
    static let danger = Color(nsColor: .systemRed)
    /// The "Not a known cache" tag and warning note.
    static let warning = Color(nsColor: .systemOrange)
    static let success = Color(nsColor: .systemGreen)
}

/// The panel's small grey pill buttons (Clear, Add): chip fill that deepens on hover.
struct VaporPillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        VaporPillButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct VaporPillButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let prominent: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: prominent ? .semibold : .medium))
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)
            .background(fill, in: .rect(cornerRadius: prominent ? 9 : 8, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .onHover { hovered = $0 && isEnabled }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private var fill: Color {
        if prominent { return Color.accentColor.opacity(hovered ? 0.88 : 1) }
        return hovered ? VaporStyle.line2 : VaporStyle.chip
    }
}

/// A round × button: grey, turning red with a white × on hover.
struct VaporCloseButton: View {
    var diameter: CGFloat = 20
    var redOnHover = true
    let label: LocalizedStringResource
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: diameter * 0.42, weight: .bold))
                .foregroundStyle(hovered && redOnHover ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: diameter, height: diameter)
                .background(hovered && redOnHover ? VaporStyle.danger : VaporStyle.chip, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}
