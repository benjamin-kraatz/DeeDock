import Foundation

/// Immutable, shareable ownership of temporary user-selected file access.
/// The original URLs survive validation and handoff; no bookmarks or documents are persisted.
nonisolated final class DocumentResourceAccess: Sendable {
    let urls: [URL]
    private let scopedURLs: [URL]
    private let stopAccess: @Sendable (URL) -> Void

    init(_ urls: [URL], startAccess: @Sendable (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         stopAccess: @escaping @Sendable (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        var seen = Set<URL>()
        self.urls = urls.filter { seen.insert($0.standardizedFileURL).inserted }
        self.stopAccess = stopAccess
        scopedURLs = self.urls.filter(startAccess)
    }

    deinit { scopedURLs.forEach(stopAccess) }
}
