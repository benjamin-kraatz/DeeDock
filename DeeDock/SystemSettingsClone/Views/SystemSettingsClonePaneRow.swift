import SwiftUI

/// One destination: symbol, title, “Opens System Settings → …” subtitle, and a chevron.
struct SystemSettingsClonePaneRow: View {
    let pane: SystemSettingsClonePane
    let colors: [Color]
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var subtitle: LocalizedStringResource {
        .systemSettingsCloneSubtitle(pane: String(localized: pane.title))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SystemSettingsCloneIconTile(symbolName: pane.symbolName, colors: colors, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pane.title)
                        .font(.body.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, SystemSettingsCloneMetrics.rowInset)
            .padding(.vertical, SystemSettingsCloneMetrics.rowVerticalInset)
            .frame(maxWidth: .infinity, minHeight: SystemSettingsCloneMetrics.rowMinimumHeight, alignment: .leading)
            .contentShape(.rect)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovering ? SystemSettingsClonePalette.copper.opacity(0.10) : .clear)
            }
        }
        .buttonStyle(.plain)
        .help(Text(subtitle))
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeOut(duration: 0.16)) { isHovering = hovering }
            }
        }
    }
}

#if DEBUG
#Preview("Pane row") {
    SystemSettingsClonePaneRow(
        pane: SystemSettingsDeepLinkCatalog.allPanes[0],
        colors: SystemSettingsClonePalette.tileColors(for: .meAndPrivacy),
        action: {}
    )
    .padding()
    .frame(width: 520)
}
#endif
