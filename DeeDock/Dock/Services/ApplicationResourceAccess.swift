import Foundation

/// Owns one balanced security-scope lease. Keep it alive across asynchronous Launch Services calls.
final class ApplicationResourceAccess {
    let url: URL
    private let scoped: Bool

    init(_ reference: ApplicationReference) {
        var stale = false
        let resolved = reference.bookmarkData.flatMap {
            try? URL(resolvingBookmarkData: $0, options: [.withSecurityScope, .withoutUI],
                     relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        url = resolved ?? reference.url
        scoped = url.startAccessingSecurityScopedResource()
    }

    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}
