import AppKit

/// An app's name and icon as macOS reports them for a bundle identifier. Names are never translated.
struct AppHealthAppDisplay: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage?

    var id: String { bundleID }

    /// Looks the app up through Launch Services. Falls back to the bundle identifier when the app is gone.
    static func live(_ bundleID: String) -> AppHealthAppDisplay {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            return AppHealthAppDisplay(bundleID: bundleID, name: bundleID, icon: nil)
        }
        let bundle = Bundle(url: url)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return AppHealthAppDisplay(bundleID: bundleID, name: name, icon: workspace.icon(forFile: url.path))
    }
}
