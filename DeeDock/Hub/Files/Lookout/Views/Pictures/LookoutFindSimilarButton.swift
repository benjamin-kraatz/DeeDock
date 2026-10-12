import SwiftUI

/// Find Similar in the preview column (the mockup's `.simbtn`): a full-width Lookout-tinted button with ⌘⇧L, or the
/// same shape disabled with why: "Lookout doesn't read this kind of file", or "Lookout hasn't read this file yet" for
/// a document the index doesn't hold (`LookoutSimilarAvailability.disabledReason`). The caller hides it for folders
/// and before Lookout is set up (`LookoutSimilarAvailability.hidden`). Search results and the browser show the same
/// button.
struct LookoutFindSimilarButton: View {
    let availability: LookoutSimilarAvailability
    let action: () -> Void

    private var isAvailable: Bool { availability.isAvailable }
    private var reason: LocalizedStringResource { availability.disabledReason ?? .lookoutSimilarUnsupported }

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        let lookout = LookoutTheme(scheme)
        let theme = HubFilesTheme(scheme)
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Button(action: action) {
            HStack(spacing: 7) {
                if isAvailable {
                    Image(systemName: "photo.badge.magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .accessibilityHidden(true)
                    Text(.lookoutSimilarButton)
                        .font(.system(size: 12.5, weight: .semibold))
                    // The mockup's `kbd`: a hairline in the system accent, like the button's own edge.
                    Text(verbatim: "⌘⇧L")
                        .font(.system(size: 10.5, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(theme.accentLine, lineWidth: 1) }
                        .accessibilityHidden(true)
                } else {
                    Text(reason)
                        .font(.system(size: 12.5))
                        .multilineTextAlignment(.center)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(isAvailable ? AnyShapeStyle(lookout.accent) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            // Hover takes the selection fill (the mockup's `--accentSel`); the edge is the selection hairline.
            .background(isAvailable ? (hovered ? theme.accentSelection : lookout.accentSoft) : theme.chip, in: shape)
            .overlay {
                if isAvailable { shape.strokeBorder(theme.accentLine, lineWidth: 0.5) }
            }
            .opacity(isAvailable ? 1 : 0.5)
            .contentShape(shape)
        }
        .buttonStyle(.hubPress(scale: 0.98))
        .disabled(!isAvailable)
        .onHover { hovered = $0 }
        .animation(HubFilesMotion.quick, value: hovered)
        .help(isAvailable ? Text(.lookoutSimilarHint) : Text(reason))
        .accessibilityHint(isAvailable ? Text(.lookoutSimilarHint) : Text(verbatim: ""))
    }
}

#Preview("Find Similar") {
    VStack(spacing: 10) {
        LookoutFindSimilarButton(availability: .available(isPicture: true)) {}
        LookoutFindSimilarButton(availability: .unsupported) {}
        LookoutFindSimilarButton(availability: .notIndexed) {}
    }
    .frame(width: 240)
    .padding()
    .background(.regularMaterial)
}
