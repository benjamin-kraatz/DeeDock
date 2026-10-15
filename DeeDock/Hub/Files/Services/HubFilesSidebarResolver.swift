import Foundation

/// Finds where an added sidebar folder is now. Called off the main actor; may block on disk I/O.
nonisolated protocol HubFilesSidebarResolving: Sendable {
    func resolve(_ folder: HubFilesSidebarFolder) -> HubFilesSidebarResolution
}

/// The live resolver: bookmark first, then the last known path.
///
/// Bookmarks resolve with `.withoutMounting` and `.withoutUI`, so a folder on an unplugged drive
/// or an unreachable share reports "not connected" instead of mounting it or asking for a password.
/// DOKK isn't sandboxed, so plain (not security-scoped) bookmarks are enough.
nonisolated struct HubFilesSidebarBookmarkResolver: HubFilesSidebarResolving {
    func resolve(_ folder: HubFilesSidebarFolder) -> HubFilesSidebarResolution {
        let fileManager = FileManager.default
        var refreshed: Data?
        var candidate: URL?

        if let bookmark = folder.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                candidate = HubFilesPath.normalized(url)
                if stale { refreshed = try? url.bookmarkData() }
            }
        }

        if candidate.map(Self.isFolder) != true {
            if let volume = Self.unmountedVolume(of: folder) {
                return Self.resolution(.disconnected(volume: volume), url: folder.url)
            }
            // The bookmark is gone or broken: fall back to the last known path and bookmark it afresh.
            candidate = Self.isFolder(folder.url) ? folder.url : nil
            refreshed = try? candidate?.bookmarkData()
        }

        guard let url = candidate, !Self.isInTrash(url) else {
            return Self.resolution(.missing, url: candidate ?? folder.url)
        }
        var resolution = Self.resolution(.available, url: url)
        resolution.name = fileManager.displayName(atPath: FilePathCopy.path(of: url))
        resolution.refreshedBookmark = refreshed
        return resolution
    }

    private static func resolution(_ status: HubFilesSidebarResolution.Status, url: URL) -> HubFilesSidebarResolution {
        let parent = HubFilesPath.parent(of: url)
        return HubFilesSidebarResolution(
            status: status, url: url, name: url.lastPathComponent,
            parentName: parent.map { FileManager.default.displayName(atPath: FilePathCopy.path(of: $0)) } ?? "",
            refreshedBookmark: nil)
    }

    private static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: FilePathCopy.path(of: url), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Items moved to the Trash keep resolving through their bookmark; Finder treats them as gone.
    private static func isInTrash(_ url: URL) -> Bool {
        let path = FilePathCopy.path(of: url)
        return path.contains("/.Trash/") || path.hasSuffix("/.Trash") || path.contains("/.Trashes/")
    }

    /// The name of the volume the folder lives on when that volume isn't mounted, else nil.
    ///
    /// The bookmark remembers its volume even while it is unplugged; without one, a path under
    /// /Volumes names it.
    private static func unmountedVolume(of folder: HubFilesSidebarFolder) -> String? {
        var volumeURL: URL?
        var volumeName: String?
        if let bookmark = folder.bookmark,
           let values = URL.resourceValues(forKeys: [.volumeURLKey, .volumeNameKey], fromBookmarkData: bookmark) {
            volumeURL = values.volume
            volumeName = values.volumeName
        }
        if volumeURL == nil {
            let parts = folder.path.split(separator: "/")
            guard parts.count >= 2, parts[0] == "Volumes" else { return nil }
            volumeURL = URL(filePath: "/Volumes/\(parts[1])", directoryHint: .isDirectory)
            volumeName = String(parts[1])
        }
        // Only volumes under /Volumes can be unplugged. A bookmark may name the internal Data
        // volume (/System/Volumes/Data), which the mounted list skips but is always there.
        guard let volumeURL, FilePathCopy.path(of: volumeURL).hasPrefix("/Volumes/") else { return nil }
        let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                             options: [.skipHiddenVolumes]) ?? []
        guard !mounted.contains(where: { HubFilesPath.same($0, volumeURL) }) else { return nil }
        return volumeName ?? volumeURL.lastPathComponent
    }
}

/// A resolver over a fixed set of folder paths, for previews and tests. Never touches the disk.
nonisolated struct HubFilesSidebarStaticResolver: HubFilesSidebarResolving {
    /// Paths that exist.
    var folders: Set<String>
    /// Volume names that are not mounted; folders under /Volumes/<name> report "not connected".
    var unmountedVolumes: Set<String> = []

    func resolve(_ folder: HubFilesSidebarFolder) -> HubFilesSidebarResolution {
        let url = folder.url
        let parts = folder.path.split(separator: "/")
        let parentName = HubFilesPath.parent(of: url)?.lastPathComponent ?? ""
        let status: HubFilesSidebarResolution.Status
        if parts.count >= 2, parts[0] == "Volumes", unmountedVolumes.contains(String(parts[1])) {
            status = .disconnected(volume: String(parts[1]))
        } else {
            status = folders.contains(folder.path) ? .available : .missing
        }
        return HubFilesSidebarResolution(status: status, url: url, name: url.lastPathComponent,
                                         parentName: parentName, refreshedBookmark: nil)
    }
}
