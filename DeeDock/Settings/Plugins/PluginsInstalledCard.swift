import SwiftUI

/// Every enabled plugin with its status, a Restart button while it is stopped, and its Pinned
/// switch. A plugin that appears while the page is open slides in with a brief accent wash.
struct PluginsInstalledCard: View {
    let plugins: [DockPlugin]
    let pinnedIDs: Set<String>
    let setPinned: (String, Bool) -> Void
    let restart: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Plugins listed when the page appeared; anything else is new and gets the arrival wash.
    @State private var initialIDs: Set<String>?

    var body: some View {
        SettingsCard(title: .pluginsInstalledTitle, footnote: .pluginsInstalledFootnote) {
            if plugins.isEmpty {
                Text(.pluginsNoneEnabled)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, SettingsMetrics.rowInset)
                    .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinimumHeight, alignment: .leading)
            }
            ForEach(plugins) { plugin in
                PluginSettingsRow(plugin: plugin, isPinned: pinnedIDs.contains(plugin.id),
                                  isNew: initialIDs.map { !$0.contains(plugin.id) } ?? false,
                                  setPinned: { setPinned(plugin.id, $0) }, restart: { restart(plugin.id) })
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear { if initialIDs == nil { initialIDs = Set(plugins.map(\.id)) } }
    }
}

/// One plugin: its icon, name, where it comes from, how it is doing, and its Pinned switch.
struct PluginSettingsRow: View {
    let plugin: DockPlugin
    let isPinned: Bool
    /// Plays the arrival wash once.
    let isNew: Bool
    let setPinned: (Bool) -> Void
    let restart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var washed = false

    var body: some View {
        HStack(spacing: 11) {
            Image(nsImage: plugin.app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                .saturation(plugin.isStopped ? 0 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: plugin.title)
                    .lineLimit(1)
                PluginStatusLine(plugin: plugin, isPinned: isPinned)
            }
            .layoutPriority(1)
            Spacer(minLength: SettingsMetrics.controlSpacing)
            if plugin.isStopped && isPinned {
                Button(action: restart) { Text(.pluginPanelRestart) }
                    .controlSize(.small)
                    .transition(.opacity)
            }
            Toggle(isOn: Binding(get: { isPinned }, set: setPinned)) { Text(.pluginsPinned) }
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel(Text(.pluginsPinnedAccessibility(plugin.title)))
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, SettingsMetrics.rowVerticalInset)
        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinimumHeight, alignment: .leading)
        .background(Color.accentColor.opacity(isNew && !washed ? 0.18 : 0))
        .onAppear {
            guard isNew, !washed else { return }
            withAnimation(reduceMotion ? .linear(duration: 0.25) : .easeOut(duration: 0.9)) { washed = true }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: plugin.status)
        .accessibilityElement(children: .contain)
    }
}

/// "From <app> · ● Running": where the plugin comes from and its status, with a coloured dot.
private struct PluginStatusLine: View {
    let plugin: DockPlugin
    let isPinned: Bool

    private var status: (title: LocalizedStringResource, color: Color) {
        guard isPinned else { return (.pluginStatusNotRunning, Color(nsColor: .tertiaryLabelColor)) }
        switch plugin.status {
        case .running: return (.pluginStatusRunning, .green)
        case .starting: return (.pluginStatusStarting, Color(nsColor: .tertiaryLabelColor))
        case .stopped: return (.pluginStatusStopped, .red)
        case .idle: return (.pluginStatusNotRunning, Color(nsColor: .tertiaryLabelColor))
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if let appName = plugin.appNameIfDifferent {
                Text(.pluginsFromApp(appName))
                Text(verbatim: "·").accessibilityHidden(true)
            }
            Circle().fill(status.color).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(status.title)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Installed") {
    PluginsInstalledCard(plugins: PluginsSettingsPreviewData.plugins, pinnedIDs: PluginsSettingsPreviewData.pinned,
                         setPinned: { _, _ in }, restart: { _ in })
        .padding(24)
        .frame(width: 640)
}

#Preview("Long names, dark") {
    PluginsInstalledCard(plugins: [PluginsSettingsPreviewData.longName], pinnedIDs: [PluginsSettingsPreviewData.longName.id],
                         setPinned: { _, _ in }, restart: { _ in })
        .padding(24)
        .frame(width: 480)
        .preferredColorScheme(.dark)
}
#endif
