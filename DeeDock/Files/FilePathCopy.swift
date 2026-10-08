import AppKit

/// Formats and copies file paths for the Copy Path and Copy Relative Path commands.
nonisolated enum FilePathCopy {
    /// The absolute POSIX path of `url`, without percent encoding or a trailing slash.
    static func path(of url: URL) -> String {
        // `path(percentEncoded:)` keeps a directory URL's trailing slash; Finder's pathname does not.
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// The path of `url` relative to `folder`, written as `./name` or `./sub/name`.
    ///
    /// A Folder Stack lists children of URLs derived from its root, so a lexical prefix match
    /// normally succeeds. When it does not, both sides are symlink-resolved to absorb aliases such
    /// as `/var` and `/private/var`. A URL outside `folder` falls back to `./` plus its own name,
    /// which is the path relative to its parent folder. `folder` itself yields `.`.
    static func relativePath(of url: URL, in folder: URL) -> String {
        let suffix = suffix(of: url.standardizedFileURL, under: folder.standardizedFileURL)
            ?? suffix(of: url.resolvingSymlinksInPath().standardizedFileURL,
                      under: folder.resolvingSymlinksInPath().standardizedFileURL)
            ?? [url.lastPathComponent]
        return suffix.isEmpty ? "." : (["."] + suffix).joined(separator: "/")
    }

    /// Replaces the general pasteboard with `paths`, one per line.
    ///
    /// Plain text only, so pasting into Terminal or an editor inserts the path rather than a file.
    @MainActor static func copy(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
    }

    /// The components of `url` after `folder`, or nil when `url` is not `folder` or inside it.
    private static func suffix(of url: URL, under folder: URL) -> [String]? {
        let child = components(url), parent = components(folder)
        guard child.count >= parent.count, Array(child.prefix(parent.count)) == parent else { return nil }
        return Array(child.dropFirst(parent.count))
    }

    /// `standardizedFileURL` drops a trailing slash, but a directory URL can still end in an empty component.
    private static func components(_ url: URL) -> [String] {
        url.pathComponents.filter { !$0.isEmpty }
    }
}
