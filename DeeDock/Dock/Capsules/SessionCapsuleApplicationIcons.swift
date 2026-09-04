import AppKit

/// Application icons for capsule window references, resolved once per bundle identifier.
///
/// The cache is small and lives for the process: a capsule references at most a dozen apps, and the
/// panel is opened repeatedly, so re-reading the bundles on every appearance is wasted disk work.
@MainActor
enum SessionCapsuleApplicationIcons {
    private static var cache: [String: NSImage] = [:]

    /// Distinct application icons for a capsule's windows, in the order the user selected them.
    ///
    /// Every distinct application is resolved, not only the few a badge can draw, so callers can show
    /// a count for the remainder. A capsule holds at most a dozen windows and the icons are cached.
    static func icons(for windows: [SessionCapsuleWindowReference],
                      limit: Int = SessionCapsuleDocument.maximumWindowsPerCapsule) -> [NSImage] {
        var seen: Set<String> = []
        var icons: [NSImage] = []
        for window in windows {
            guard let bundleIdentifier = window.bundleIdentifier, seen.insert(bundleIdentifier).inserted,
                  let icon = icon(for: bundleIdentifier) else { continue }
            icons.append(icon)
            if icons.count == limit { break }
        }
        return icons
    }

    static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier else { return nil }
        if let cached = cache[bundleIdentifier] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 44, height: 44)
        cache[bundleIdentifier] = image
        return image
    }
}
