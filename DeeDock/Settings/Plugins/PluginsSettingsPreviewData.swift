#if DEBUG
import AppKit
import UniformTypeIdentifiers

/// Fixed plugins for the Plugins page previews. No ExtensionKit identities, so nothing launches.
@MainActor
enum PluginsSettingsPreviewData {
    private static var icon: NSImage { NSWorkspace.shared.icon(for: .applicationBundle) }

    static let plugins: [DockPlugin] = [
        DockPlugin(id: "com.example.Reader.Plugin", extensionName: "Reader",
                   app: DockPluginApp(name: "Reader", url: nil, icon: icon), status: .running),
        DockPlugin(id: "com.example.Pipeline.BuildStatus", extensionName: "Build Status",
                   app: DockPluginApp(name: "Pipeline", url: nil, icon: icon), status: .stopped),
        DockPlugin(id: "de.benjaminkraatz.DOKKSamplePlugin.Extension", extensionName: "DOKK Sample Plugin",
                   app: DockPluginApp(name: "DOKK Sample Plugin", url: nil, icon: icon), status: .running),
        DockPlugin(id: "com.example.Glance.Weather", extensionName: "Weather Glance",
                   app: DockPluginApp(name: "Glance", url: nil, icon: icon), status: .idle),
    ]

    static let pinned: Set<String> = Set(plugins.prefix(3).map(\.id))

    static let longName = DockPlugin(
        id: "com.example.Long.Plugin", extensionName: "A Plugin With an Unusually Long and Descriptive Name",
        app: DockPluginApp(name: "Long-Named Productivity Suite Professional", url: nil, icon: icon), status: .stopped)
}
#endif
