import SwiftUI

/// The Plugins section: what plugins are, how many wait for approval, and every enabled plugin
/// with its status and Pinned switch.
///
/// Opening the page re-checks for plugins, since an install made while DOKK runs is not reported
/// on its own, and asks every running plugin for a fresh tile state.
struct PluginsSettingsPane: View {
    let controller: DockPluginController

    var body: some View {
        PluginsSettingsContent(
            plugins: controller.plugins,
            waitingCount: controller.waitingCount,
            hasInventory: controller.hasInventory,
            pinnedIDs: Set(controller.dockItems.map(\.pluginID)),
            setPinned: { controller.setPinned($0, $1, surface: .settings) },
            restart: { controller.restart($0, surface: .settings) },
            manage: { controller.showApprovalWindow() })
        .task { controller.rescan() }
    }
}

/// The page's layout over plain values, so previews show every state without ExtensionKit.
struct PluginsSettingsContent: View {
    let plugins: [DockPlugin]
    let waitingCount: Int
    /// False until discovery first reports; the page then shows a quiet spinner, not "no plugins".
    let hasInventory: Bool
    let pinnedIDs: Set<String>
    let setPinned: (String, Bool) -> Void
    let restart: (String) -> Void
    let manage: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPageScaffold {
            PluginsSettingsHero()
            if !hasInventory {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .accessibilityLabel(Text(.pluginsSettingsLooking))
            } else if plugins.isEmpty && waitingCount == 0 {
                PluginsEmptyCard(manage: manage)
                    .transition(.opacity)
            } else {
                PluginsApprovalCard(waitingCount: waitingCount, manage: manage)
                PluginsInstalledCard(plugins: plugins, pinnedIDs: pinnedIDs, setPinned: setPinned, restart: restart)
            }
        }
        .navigationTitle(Text(.pluginsSettingsTitle))
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: plugins.map(\.id))
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: waitingCount)
    }
}

#if DEBUG
#Preview("Plugins and one waiting") {
    PluginsSettingsContent(plugins: PluginsSettingsPreviewData.plugins, waitingCount: 1, hasInventory: true,
                           pinnedIDs: PluginsSettingsPreviewData.pinned, setPinned: { _, _ in }, restart: { _ in },
                           manage: {})
        .frame(width: 640, height: 620)
}

#Preview("All approved, dark") {
    PluginsSettingsContent(plugins: PluginsSettingsPreviewData.plugins, waitingCount: 0, hasInventory: true,
                           pinnedIDs: PluginsSettingsPreviewData.pinned, setPinned: { _, _ in }, restart: { _ in },
                           manage: {})
        .frame(width: 640, height: 620)
        .preferredColorScheme(.dark)
}

#Preview("Only waiting") {
    PluginsSettingsContent(plugins: [], waitingCount: 2, hasInventory: true, pinnedIDs: [],
                           setPinned: { _, _ in }, restart: { _ in }, manage: {})
        .frame(width: 640, height: 480)
}

#Preview("No plugins") {
    PluginsSettingsContent(plugins: [], waitingCount: 0, hasInventory: true, pinnedIDs: [],
                           setPinned: { _, _ in }, restart: { _ in }, manage: {})
        .frame(width: 640, height: 480)
}

#Preview("Looking") {
    PluginsSettingsContent(plugins: [], waitingCount: 0, hasInventory: false, pinnedIDs: [],
                           setPinned: { _, _ in }, restart: { _ in }, manage: {})
        .frame(width: 640, height: 400)
}
#endif
