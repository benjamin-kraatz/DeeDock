import AppKit
import SwiftUI

/// Filename supplied by the installation, without querying metadata during view rendering.
func badgeAppName(_ path: String) -> String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }

/// Icons for the paths badge history retained, resolved once per path.
///
/// History outlives the apps it describes: a path here may name a bundle that has been moved or
/// deleted, which `NSWorkspace` answers with a generic icon rather than a failure. Caching keeps
/// a list of up to 100 rows free of repeated lookups while scrolling.
@MainActor
enum BadgeAppArtwork {
    private static var cache: [String: NSImage] = [:]

    static func icon(_ path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 64, height: 64)
        cache[path] = icon
        return icon
    }

    /// The app's own color for panel surfaces, or `nil` for achromatic artwork.
    static func tint(_ path: String, dark: Bool) -> Color? {
        DockIconAccent.surface(for: icon(path), identity: path, dark: dark)
    }

    /// Drops cached artwork; the next request re-reads the bundle.
    static func invalidate() { cache.removeAll() }
}
