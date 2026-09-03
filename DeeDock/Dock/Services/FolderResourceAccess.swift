import Foundation

/// Owns resolved, security-scoped access to one pinned folder.
nonisolated final class FolderResourceAccess: @unchecked Sendable {
    let url: URL
    let bookmarkIsStale: Bool
    private let scoped: Bool
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
        self.stopAccess = stopAccess
    }

    var isAvailable: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    deinit { if scoped { stopAccess(url) } }
}
