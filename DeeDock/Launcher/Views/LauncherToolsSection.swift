import SwiftUI

/// DOKK's own windows, drawn like app results but without pin, favorite, or suggestion controls.
struct LauncherToolsSection: View {
    let state: LauncherState
    let tools: [LauncherTool]
    let columns: Int
    var grid = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HubAppsSectionHeader(title: Text(.launcherToolsSectionTitle))
            if grid {
                LazyVGrid(columns: LauncherGridColumns.items(columns), spacing: HubAppsStyle.gridRowSpacing) {
                    tiles
                }
            } else {
                LazyVStack(spacing: 2) { tiles }
            }
        }
    }

    private var tiles: some View {
        ForEach(tools) { tool in
            LauncherToolButton(tool: tool, state: state, grid: grid)
        }
    }
}

private struct LauncherToolButton: View {
    let tool: LauncherTool
    let state: LauncherState
    let grid: Bool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            Group {
                if grid {
                    VStack(spacing: 8) {
                        artwork(size: HubAppsStyle.tileIconSize)
                            .scaleEffect(hovered && !reduceMotion ? HubAppsStyle.tileHoverScale : 1)
                        Text(tool.title).font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail)
                    }
                    .padding(EdgeInsets(top: 12, leading: 4, bottom: 10, trailing: 4))
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 12) {
                        artwork(size: HubAppsStyle.listIconSize)
                        Text(tool.title).font(.body.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text(.appName).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(hovered ? HubAppsStyle.chip(colorScheme) : .clear,
                        in: .rect(cornerRadius: grid ? HubAppsStyle.tileCornerRadius : HubStyle.rowRadius,
                                  style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : HubStyle.hover, value: hovered)
        .accessibilityLabel(Text(tool.title))
        .accessibilityHint(Text(.launcherOpenHint))
    }

    private func open() {
        Analytics.track(.launcherToolOpened(tool))
        if tool == .systemSettingsClone {
            // Opening a DOKK window hands focus away, so an anchored Hub dismisses.
            state.close?()
            Analytics.performing(.launcher) { openWindow.openSystemSettingsClone() }
        } else {
            state.openTool?(tool)
        }
    }

    /// An app-icon-like squircle so tools sit naturally among real app icons.
    private func artwork(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(Color.accentColor.gradient)
            .overlay {
                Image(systemName: tool.symbol)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: size * 0.84, height: size * 0.84)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
            .accessibilityHidden(true)
    }
}
