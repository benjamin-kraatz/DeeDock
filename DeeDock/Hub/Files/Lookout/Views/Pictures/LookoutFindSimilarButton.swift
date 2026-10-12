import SwiftUI

/// Find Similar in the preview column (the mockup's `.simbtn`): a full-width Lookout-tinted button with ⌘⇧L, or,
/// for a kind of file Lookout doesn't read, the same shape disabled with "Lookout doesn't read this kind of file".
/// The caller hides it for folders and before Lookout is set up (`LookoutSimilarAvailability.hidden`).
struct LookoutFindSimilarButton: View {
    let isAvailable: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        let lookout = LookoutTheme(scheme)
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Button(action: action) {
            HStack(spacing: 7) {
                if isAvailable {
                    Image(systemName: "photo.badge.magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .accessibilityHidden(true)
                    Text(.lookoutSimilarButton)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(verbatim: "⌘⇧L")
                        .font(.system(size: 10.5, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(lookout.accent.opacity(0.55), lineWidth: 1) }
                        .accessibilityHidden(true)
                } else {
                    Text(.lookoutSimilarUnsupported)
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
            .background(isAvailable ? (hovered ? Color.accentColor.opacity(0.3) : lookout.accentSoft)
                        : HubFilesTheme(scheme).chip, in: shape)
            .overlay {
                if isAvailable { shape.strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 0.5) }
            }
            .opacity(isAvailable ? 1 : 0.5)
            .contentShape(shape)
        }
        .buttonStyle(.hubPress(scale: 0.98))
        .disabled(!isAvailable)
        .onHover { hovered = $0 }
        .animation(HubFilesMotion.quick, value: hovered)
        .help(isAvailable ? Text(.lookoutSimilarHint) : Text(.lookoutSimilarUnsupported))
        .accessibilityHint(isAvailable ? Text(.lookoutSimilarHint) : Text(verbatim: ""))
    }
}

#Preview("Find Similar") {
    VStack(spacing: 10) {
        LookoutFindSimilarButton(isAvailable: true) {}
        LookoutFindSimilarButton(isAvailable: false) {}
    }
    .frame(width: 240)
    .padding()
    .background(.regularMaterial)
}
