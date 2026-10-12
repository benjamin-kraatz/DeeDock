import SwiftUI

/// Onboarding's buttons (the mockup's `.cta`, `.cta.ghost` and `.mini`): the accent primary button, the quiet
/// secondary one in the footer, and the small one inside rows. Disabled ones fade to 40 %; a press scales down a
/// little, without motion under Reduce Motion.
struct LookoutSetupButtonStyle: ButtonStyle {
    enum Kind {
        case primary, secondary, mini
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        LookoutSetupButtonBody(kind: kind, configuration: configuration)
    }
}

private struct LookoutSetupButtonBody: View {
    let kind: LookoutSetupButtonStyle.Kind
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        let theme = HubFilesTheme(scheme)
        configuration.label
            .font(kind == .mini ? .system(size: 12) : .system(size: 12.5, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(kind == .primary ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, kind == .mini ? 11 : 13)
            .padding(.vertical, kind == .mini ? 5 : 6)
            .background(kind == .primary ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(theme.chipHighlight),
                        in: .rect(cornerRadius: kind == .mini ? 7 : 8, style: .continuous))
            .brightness(hovered && isEnabled ? 0.05 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !HubFilesMotion.reduceMotion ? 0.97 : 1)
            .animation(HubFilesMotion.quick, value: configuration.isPressed)
            .contentShape(.rect)
            .onHover { hovered = $0 }
            .fixedSize()
    }
}

extension ButtonStyle where Self == LookoutSetupButtonStyle {
    static var lookoutPrimary: LookoutSetupButtonStyle { LookoutSetupButtonStyle(kind: .primary) }
    static var lookoutSecondary: LookoutSetupButtonStyle { LookoutSetupButtonStyle(kind: .secondary) }
    static var lookoutMini: LookoutSetupButtonStyle { LookoutSetupButtonStyle(kind: .mini) }
}

/// A step's title and the line under it (the mockup's `h2` and `.lead`).
struct LookoutSetupHeading: View {
    let title: LocalizedStringResource
    let lead: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LookoutSetupTitle(title)
            LookoutSetupLead(lead)
        }
        .padding(.bottom, 18)
    }
}

/// A step's 22 pt title.
struct LookoutSetupTitle: View {
    let text: LocalizedStringResource

    init(_ text: LocalizedStringResource) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .bold))
            .tracking(-0.2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A step's explanation under its title.
struct LookoutSetupLead: View {
    let text: LocalizedStringResource

    init(_ text: LocalizedStringResource) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The rounded, outlined card behind a folder, access or download row (the mockup's `.fr`, `.acc` and `.dl`).
struct LookoutSetupRowBackground: ViewModifier {
    var radius: CGFloat = 10

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(LookoutTheme(scheme).card, in: shape)
            .overlay { shape.strokeBorder(HubFilesTheme(scheme).line, lineWidth: 0.5) }
    }
}

extension View {
    /// Draws onboarding's row card behind the view.
    func lookoutSetupRow(radius: CGFloat = 10) -> some View {
        modifier(LookoutSetupRowBackground(radius: radius))
    }
}

#Preview("Buttons") {
    HStack(spacing: 10) {
        Button(.lookoutSetupNotNow) {}.buttonStyle(.lookoutSecondary)
        Button(.lookoutSetupContinue) {}.buttonStyle(.lookoutPrimary)
        Button(.lookoutSetupContinue) {}.buttonStyle(.lookoutPrimary).disabled(true)
        Button(.lookoutSetupAllow) {}.buttonStyle(.lookoutMini)
    }
    .padding(24)
    .background(.regularMaterial)
}
