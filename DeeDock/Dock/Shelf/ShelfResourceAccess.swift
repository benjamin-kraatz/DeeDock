import Foundation

/// Owns resolved, security-scoped access to one staged file for as long as it is needed.
///
/// A drag out of the Shelf must keep its scope alive until the receiving application has finished
/// reading, so the dragging source holds these objects for the whole session.
nonisolated final class ShelfResourceAccess: @unchecked Sendable {
    let id: UUID
    let url: URL
    let bookmarkIsStale: Bool
    private let scoped: Bool
    private let stopAccess: (URL) -> Void

    init(_ item: ShelfItem,
         startAccess: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         stopAccess: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        id = item.id
        var stale = false
        let resolved = try? URL(resolvingBookmarkData: item.bookmarkData,
                                options: [.withSecurityScope, .withoutUI],
                                relativeTo: nil, bookmarkDataIsStale: &stale)
        url = (resolved ?? item.url).standardizedFileURL
        bookmarkIsStale = stale
        scoped = startAccess(url)
        self.stopAccess = stopAccess
    }

    /// Files and folders are both valid Shelf contents, so existence alone decides.
    var isAvailable: Bool { FileManager.default.fileExists(atPath: url.path) }

    deinit { if scoped { stopAccess(url) } }
}
