import Foundation

/// Owns resolved, security-scoped access to one pinned folder.
nonisolated final class FolderResourceAccess: @unchecked Sendable {
    let url: URL
    let bookmarkIsStale: Bool
    private let scoped: Bool
    /// Stack opens resolve on `VolumeReads`, so the matching stop runs there too.
    private let releaseOnVolumeReads: Bool
    private let stopAccess: (URL) -> Void

    init(_ reference: FolderReference,
         startAccess: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         stopAccess: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        var stale = false
        let resolved = try? URL(resolvingBookmarkData: reference.bookmarkData,
                                options: [.withSecurityScope, .withoutUI],
                                relativeTo: nil, bookmarkDataIsStale: &stale)
        url = (resolved ?? reference.url).standardizedFileURL
        bookmarkIsStale = stale
        scoped = startAccess(url)
        releaseOnVolumeReads = scoped && VolumeReads.isCurrent
        self.stopAccess = stopAccess
    }

    /// `fileExists` can stall on a wedged volume. Stack opens call this from `VolumeReads`.
    var isAvailable: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    deinit {
        guard scoped else { return }
        if releaseOnVolumeReads {
            let url = url
            VolumeReads.enqueue { url.stopAccessingSecurityScopedResource() }
        } else {
            stopAccess(url)
        }
    }
}
