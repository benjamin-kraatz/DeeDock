import Foundation

/// Path helpers for locations, breadcrumbs, and column chains. Pure string work, no file I/O.
nonisolated enum HubFilesPath {
    /// `url` as a file URL without a trailing slash, so a folder from a listing (which may end in
    /// "/") equals the same folder built from a path. Built with `.notDirectory` to avoid a stat.
    static func normalized(_ url: URL) -> URL {
        URL(filePath: FilePathCopy.path(of: url), directoryHint: .notDirectory)
    }

    /// True when both URLs name the same path.
    static func same(_ a: URL, _ b: URL) -> Bool {
        FilePathCopy.path(of: a) == FilePathCopy.path(of: b)
    }

    /// True when `url` is `folder` or inside it.
    static func contains(_ folder: URL, _ url: URL) -> Bool {
        let parent = FilePathCopy.path(of: folder), child = FilePathCopy.path(of: url)
        if parent == "/" { return true }
        return child == parent || child.hasPrefix(parent + "/")
    }

    /// The parent folder, or nil for the file-system root.
    static func parent(of url: URL) -> URL? {
        let path = FilePathCopy.path(of: url)
        guard path != "/" else { return nil }
        return normalized(url.deletingLastPathComponent())
    }

    /// True for "/" and for a mounted volume's root under /Volumes.
    static func isVolumeRoot(_ url: URL) -> Bool {
        let path = FilePathCopy.path(of: url)
        if path == "/" { return true }
        let parts = path.split(separator: "/")
        return parts.count == 2 && parts[0] == "Volumes"
    }

    /// Folders from the nearest anchor down to `folder`, inclusive.
    ///
    /// Anchors are the sidebar's folders and volume roots, so a breadcrumb or column view starts
    /// where the user would have started browsing (the mockup's `crumbs()`). A folder outside
    /// every anchor starts at its volume root.
    static func chain(to folder: URL, anchors: [URL]) -> [URL] {
        let anchorPaths = Set(anchors.map(FilePathCopy.path(of:)))
        var chain: [URL] = []
        var current: URL? = normalized(folder)
        while let url = current {
            chain.append(url)
            if anchorPaths.contains(FilePathCopy.path(of: url)) || isVolumeRoot(url) { break }
            current = parent(of: url)
        }
        return chain.reversed()
    }

    /// The path shown in the search Where column: the home folder abbreviated to "~".
    static func abbreviated(_ url: URL, home: URL) -> String {
        let path = FilePathCopy.path(of: url), homePath = FilePathCopy.path(of: home)
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }
}
