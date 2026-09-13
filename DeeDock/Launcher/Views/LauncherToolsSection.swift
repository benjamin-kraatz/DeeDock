import SwiftUI

/// DDock's own windows, drawn like app results but without pin, favorite, or suggestion controls.
struct LauncherToolsSection: View {
    let state: LauncherState
    let tools: [LauncherTool]
    let columns: Int
    var grid = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.launcherToolsSectionTitle)
                .font(.headline).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader).padding(.leading, 12)
            if grid {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: max(1, columns)), spacing: 0) {
                    tiles
                }
            } else {
                LazyVStack(spacing: 0) { tiles }
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
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            Group {
                if grid {
                    VStack(spacing: 8) {
                        artwork(size: 60)
                        Text(tool.title).font(.callout).lineLimit(2)
                            .allowsTightening(true).minimumScaleFactor(0.9)
                            .multilineTextAlignment(.center).frame(height: 34, alignment: .top)
                    }
                    .padding(10).frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 12) {
                        artwork(size: 34)
                        Text(tool.title).font(.body.bold()).lineLimit(1)
                        Spacer()
                        Text(.appName).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color.primary.opacity(hovered ? 0.06 : 0), in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(Text(tool.title))
        .accessibilityHint(Text(.launcherOpenHint))
    }

    private func open() {
        if tool == .systemSettingsClone {
            state.close?()
            openWindow.openSystemSettingsClone()
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
