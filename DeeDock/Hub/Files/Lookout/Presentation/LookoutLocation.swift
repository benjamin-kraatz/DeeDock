import Foundation

/// Where a Lookout hit is, as its row shows it: the enclosing folders from the home folder down, joined with " › "
/// ("Desktop › Holiday Sylt 2026").
///
/// Pure string work on the absolute path the index stores; no file I/O.
/// - A file directly in the home folder shows the home folder's name.
/// - Under home, the first folder can be renamed by `localizedName` (Desktop shows as "Schreibtisch" in German, as
///   in Finder's sidebar).
/// - On another volume the path starts at the volume's name ("USB-Stick › Photos").
/// - Anywhere else the full path's folders show, or "/" for the root.
nonisolated enum LookoutLocation {
    static let separator = " › "

    /// - Parameters:
    ///   - path: The hit's absolute path (a file's or a folder's).
    ///   - home: The home folder's path.
    ///   - localizedName: A display name for a folder path, or nil to use the folder's own name.
    static func text(forParentOf path: String, home: String,
                     localizedName: (String) -> String? = { _ in nil }) -> String {
        let parent = trimmed((path as NSString).deletingLastPathComponent)
        let home = trimmed(home)
        if parent == home {
            return localizedName(home) ?? (home as NSString).lastPathComponent
        }
        if parent.hasPrefix(home + "/") {
            var parts = parent.dropFirst(home.count + 1).split(separator: "/").map(String.init)
            if let first = parts.first, let name = localizedName(home + "/" + first) { parts[0] = name }
            return parts.joined(separator: separator)
        }
        let parts = parent.split(separator: "/").map(String.init)
        if parts.count >= 2, parts[0] == "Volumes" {
            return parts.dropFirst().joined(separator: separator)
        }
        return parts.isEmpty ? "/" : parts.joined(separator: separator)
    }

    private static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
