import SwiftUI
import UniformTypeIdentifiers

/// A plugin's panel: DOKK's header and glass around content the plugin draws in its own process.
///
/// While the plugin is stopped the content dims behind a calm "stopped · Restart" notice. Restart
/// keeps the notice up with a spinner until the plugin answers, then the scene reloads in place.
struct DockPluginPanel: View {
    let plugin: DockPlugin
    let state: DockPluginPanelState

    var body: some View {
        DockPluginPanelView(plugin: plugin, state: state) {
            // A stopped plugin has no scene: hosting one would launch its process behind DOKK's
            // back. Restart brings the scene back with the session.
            if let identity = plugin.identity, plugin.status != .stopped {
                DockPluginSceneHost(identity: identity, failed: { state.sceneFailed?() })
                    // A restart or an updated plugin raises the generation: a fresh host, a fresh scene.
                    .id(plugin.sceneGeneration)
            }
        }
    }
}

/// The panel's layout, with the plugin's content passed in so previews can stand in for the
/// remote scene.
struct DockPluginPanelView<Content: View>: View {
    let plugin: DockPlugin
    let state: DockPluginPanelState
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Shown while stopped, and after a restart from here until the plugin is back.
    private var showsStopped: Bool {
        plugin.status == .stopped || (state.restarting && plugin.status == .starting)
    }

    var body: some View {
        VStack(spacing: 0) {
            DockPluginPanelHeader(icon: plugin.app.icon, title: plugin.title, appName: plugin.appNameIfDifferent) {
                DockPluginMoreButton(plugin: plugin, state: state)
            }
            ZStack {
                content
                    .opacity(showsStopped ? 0.16 : 1)
                    .allowsHitTesting(!showsStopped)
                    .accessibilityHidden(showsStopped)
                if showsStopped {
                    DockPluginStoppedView(title: plugin.title, restarting: plugin.status == .starting) {
                        state.restart?()
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .dockPopoverChrome(state.chrome, opaque: reduceTransparency)
        // The notice and the dimming only fade, so Reduce Motion keeps a shorter cross-fade
        // rather than a cut.
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3), value: showsStopped)
        .onChange(of: plugin.status) { _, status in
            if status == .running { state.restarting = false }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: plugin.title))
    }
}

#if DEBUG
/// Stand-in content for previews: the remote scene cannot run there.
private struct DockPluginPanelPreviewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "CONTINUE READING").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            Text(verbatim: "The Name of the Rose").font(.headline)
            Text(verbatim: "Umberto Eco · 62% read").font(.caption).foregroundStyle(.secondary)
            ProgressView(value: 0.62).tint(.green).frame(width: 170)
            Spacer()
            HStack { Spacer(); Button(String("Open in philos")) {}.buttonStyle(.borderedProminent) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

@MainActor private func previewPlugin(status: DockPluginStatus) -> DockPlugin {
    DockPlugin(id: "com.example.philos.Plugin", extensionName: "philos",
               app: DockPluginApp(name: "philos", url: nil, icon: NSWorkspace.shared.icon(for: .applicationBundle)),
               tileState: DOKKPluginTileState(badge: .count(2), panelSize: DOKKPluginSize(width: 360, height: 280)),
               status: status)
}

#Preview("Running") {
    let state = DockPluginPanelState()
    state.chrome = DockPopoverChrome(edge: .bottom, attachment: 180)
    return DockPluginPanelView(plugin: previewPlugin(status: .running), state: state) { DockPluginPanelPreviewContent() }
        .frame(width: 360, height: 330)
        .padding(30)
}

#Preview("Stopped, dark") {
    let state = DockPluginPanelState()
    state.chrome = DockPopoverChrome(edge: .bottom, attachment: 180)
    return DockPluginPanelView(plugin: previewPlugin(status: .stopped), state: state) { DockPluginPanelPreviewContent() }
        .frame(width: 360, height: 330)
        .padding(30)
        .preferredColorScheme(.dark)
}

#Preview("Minimum size, left dock") {
    let state = DockPluginPanelState()
    state.chrome = DockPopoverChrome(edge: .left, attachment: 110)
    return DockPluginPanelView(plugin: previewPlugin(status: .running), state: state) { DockPluginPanelPreviewContent() }
        .frame(width: 290, height: 220)
        .padding(30)
}
#endif
