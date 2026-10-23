import AppKit
import UniformTypeIdentifiers

/// The app a plugin ships in: its name and icon for the tile, and its location for "Open <app>".
struct DockPluginApp: Equatable {
    /// The app's display name as macOS gives it. Never translated by DOKK.
    let name: String
    /// Nil when LaunchServices does not know the app, for example while it is being moved.
    let url: URL?
    let icon: NSImage

    /// Finds the app containing the extension `bundleIdentifier`.
    ///
    /// An embedded extension's identifier must start with its app's identifier, so the app is found
    /// by dropping trailing components (`com.example.App.Plugin` → `com.example.App`). LaunchServices
    /// is asked about the extension itself only when that finds nothing; its bundle sits in the
    /// app's `Contents/Extensions`.
    /// - Parameter fallbackName: The extension's own name, used when no app is found.
    static func resolve(extension bundleIdentifier: String, fallbackName: String) -> DockPluginApp {
        let workspace = NSWorkspace.shared
        var components = bundleIdentifier.split(separator: ".").map(String.init)
        var url: URL?
        while components.count > 1, url == nil {
            components.removeLast()
            url = workspace.urlForApplication(withBundleIdentifier: components.joined(separator: "."))
        }
        if url == nil, let own = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            url = sequence(first: own, next: { $0.pathComponents.count > 1 ? $0.deletingLastPathComponent() : nil })
                .first { $0.pathExtension == "app" }
        }
        let icon: NSImage
        if let url {
            icon = workspace.icon(forFile: url.path)
        } else {
            icon = workspace.icon(for: .applicationExtension)
        }
        icon.size = NSSize(width: 128, height: 128)
        let name = url.map { FileManager.default.displayName(atPath: $0.path) }
            .map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 } ?? fallbackName
        return DockPluginApp(name: name, url: url, icon: icon)
    }
}
