import SwiftUI

/// One launchable destination in a section grid: icon, title, and what is inside.
///
/// Hover tints the tile with the icon's hue and reveals an "opens elsewhere" arrow.
/// `launchCount` bumps the symbol when this pane is opened.
struct SystemSettingsClonePaneTile: View {
    let pane: SystemSettingsClonePane
    let launchCount: Int
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SystemSettingsCloneIconTile(symbolName: pane.symbolName, tint: pane.tint, size: 34)
                    .scaleEffect(isHovering && !reduceMotion ? 1.06 : 1)
                    .symbolEffect(.bounce, value: launchCount)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pane.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(pane.detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(pane.tint.accent)
                    .opacity(isHovering ? 1 : 0)
                    .offset(x: isHovering || reduceMotion ? 0 : -4, y: isHovering || reduceMotion ? 0 : 4)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: SystemSettingsCloneMetrics.tileRadius, style: .continuous)
                    .fill(pane.tint.accent.opacity(isHovering ? 0.13 : 0))
            }
            .contentShape(.rect(cornerRadius: SystemSettingsCloneMetrics.tileRadius))
        }
        .buttonStyle(SystemSettingsClonePressStyle())
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { isHovering = hovering }
        }
        .accessibilityLabel(Text(pane.title))
        .accessibilityValue(Text(pane.detail))
        .accessibilityHint(Text(.systemSettingsCloneOpenHint))
    }
}

/// Larger icon-over-label launcher used in Quick Access.
struct SystemSettingsCloneQuickTile: View {
    let pane: SystemSettingsClonePane
    let launchCount: Int
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                SystemSettingsCloneIconTile(symbolName: pane.symbolName, tint: pane.tint, size: 46)
                    .scaleEffect(isHovering && !reduceMotion ? 1.08 : 1)
                    .offset(y: isHovering && !reduceMotion ? -2 : 0)
                    .symbolEffect(.bounce, value: launchCount)
                Text(pane.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 30, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .padding(.horizontal, 4)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(pane.tint.accent.opacity(isHovering ? 0.12 : 0))
            }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(SystemSettingsClonePressStyle())
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.3)) { isHovering = hovering }
        }
        .help(Text(pane.detail))
        .accessibilityLabel(Text(pane.title))
        .accessibilityValue(Text(pane.detail))
        .accessibilityHint(Text(.systemSettingsCloneOpenHint))
    }
}

#if DEBUG
#Preview("Tiles") {
    VStack(spacing: 20) {
        SystemSettingsClonePaneTile(pane: SystemSettingsDeepLinkCatalog.allPanes[8], launchCount: 0, action: {})
            .frame(width: 280)
        HStack {
            ForEach(SystemSettingsCloneRecents.quickAccess(from: "").prefix(5)) { pane in
                SystemSettingsCloneQuickTile(pane: pane, launchCount: 0, action: {})
                    .frame(width: 92)
            }
        }
    }
    .padding(24)
}
#endif
