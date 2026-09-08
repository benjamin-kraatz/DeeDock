import SwiftUI

/// One deliberate outbound action, with the limits of that action stated next to it.
///
/// Each of these does something different to files the user still owns — activate, copy, ask the
/// app to open — so they are rows with an explanation rather than a line of equal-looking buttons.
struct WindowFileHandoffActionRow: View {
    let symbol: String
    let title: LocalizedStringResource
    /// What the action does and does not promise. Kept visible, not hidden behind a help tag.
    let subtitle: LocalizedStringResource
    /// Destination app color, shared with the panel's header and drag handle.
    let tint: Color
    let enabled: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .background(hovering && enabled ? AnyShapeStyle(.quaternary.opacity(0.7)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 10))
        .opacity(enabled ? 1 : 0.45)
        .onHover { value in
            guard !reduceMotion else { hovering = value; return }
            withAnimation(.easeOut(duration: 0.12)) { hovering = value }
        }
        .accessibilityHint(Text(subtitle))
    }
}

#if DEBUG
#Preview("Actions") {
    VStack(spacing: 2) {
        WindowFileHandoffActionRow(symbol: "macwindow.on.rectangle", title: .fileRouteActivateWindow,
                                   subtitle: .fileRouteActivateHelp, tint: .accentColor, enabled: true, action: {})
        WindowFileHandoffActionRow(symbol: "doc.on.clipboard", title: .fileRouteCopy,
                                   subtitle: .fileRouteCopyHelp, tint: .accentColor, enabled: true, action: {})
        WindowFileHandoffActionRow(symbol: "arrow.up.forward.app", title: .fileRouteOpenApp,
                                   subtitle: .fileRouteOpenHelp, tint: .accentColor, enabled: false, action: {})
    }
    .padding(26).frame(width: 540)
}
#endif
