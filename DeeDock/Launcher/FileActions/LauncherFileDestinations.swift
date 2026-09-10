import Foundation

/// A user-chosen copy destination. Removing it discards the bookmark, never the folder contents.
nonisolated struct LauncherFileDestination: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var url: URL
    var bookmarkData: Data

    init(id: UUID = UUID(), name: String, url: URL, bookmarkData: Data) {
        self.id = id
        self.name = name
        self.url = url
        self.bookmarkData = bookmarkData
    }
}

/// Versioned destination list. Unreadable bytes stay on disk until the user resets.
nonisolated struct LauncherFileDestinationsDocument: Codable, Sendable {
    static let currentVersion = 1
    static let capacity = 20

    var version: Int
    var destinations: [LauncherFileDestination]

    init(version: Int = currentVersion, destinations: [LauncherFileDestination] = []) {
        self.version = version
        self.destinations = destinations
    }

    var isValid: Bool {
        version == Self.currentVersion
            && destinations.count <= Self.capacity
            && Set(destinations.map(\.id)).count == destinations.count
            && destinations.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// Owns resolved write access to one bookmarked destination for the length of a copy.
nonisolated final class LauncherFileDestinationAccess: @unchecked Sendable {
    let url: URL
    let bookmarkIsStale: Bool
    private let scoped: Bool
    private let stopAccess: (URL) -> Void

    init(_ destination: LauncherFileDestination,
         startAccess: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         stopAccess: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        var stale = false
        let resolved = try? URL(resolvingBookmarkData: destination.bookmarkData,
                                options: [.withSecurityScope, .withoutUI],
                                relativeTo: nil, bookmarkDataIsStale: &stale)
        url = (resolved ?? destination.url).standardizedFileURL
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
