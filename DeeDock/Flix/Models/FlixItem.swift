import Foundation
import UniformTypeIdentifiers

/// One row of the activity stream: a file, folder, app, or web page and what last happened to it.
///
/// A value snapshot kept in DOKK's own history (`FlixHistory`). Sources only feed it; removing an
/// item from Flix Files never touches the file. The identity (`id`) survives later events for the
/// same path, so selection, flags, and phase B's per-item annotations stay attached.
nonisolated struct FlixItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// Standardized absolute path for files, folders, and apps. Nil for links.
    var path: String?
    /// The page for a link item. Nil for files.
    var link: FlixLink?
    /// Display name as Finder shows it, or the page title.
    var name: String
    var kind: FlixItemKind
    /// The latest thing that happened.
    var activity: FlixActivity
    /// When `activity` happened. The list is sorted by this, newest first.
    var date: Date
    /// When Flix Files first recorded the item.
    var firstSeen: Date
    /// The page a download came from (`kMDItemWhereFroms`), reduced to scheme, host, and path.
    var sourcePage: URL?
    /// The uniform type identifier, when known.
    var contentTypeIdentifier: String?
    var byteSize: Int64?
    /// Flagged items never age out of the history.
    var isFlagged: Bool
    /// Set for apps, so reopening and icons do not depend on the path.
    var bundleIdentifier: String?

    init(id: UUID = UUID(), path: String? = nil, link: FlixLink? = nil, name: String, kind: FlixItemKind,
         activity: FlixActivity, date: Date, firstSeen: Date? = nil, sourcePage: URL? = nil,
         contentTypeIdentifier: String? = nil, byteSize: Int64? = nil, isFlagged: Bool = false,
         bundleIdentifier: String? = nil) {
        self.id = id
        self.path = path
        self.link = link
        self.name = name
        self.kind = kind
        self.activity = activity
        self.date = date
        self.firstSeen = firstSeen ?? date
        self.sourcePage = sourcePage
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteSize = byteSize
        self.isFlagged = isFlagged
        self.bundleIdentifier = bundleIdentifier
    }

    /// The file URL for a file, folder, or app item.
    var url: URL? { path.map { URL(fileURLWithPath: $0) } }

    /// What a drag, a copy, or opening the item hands to macOS: the file, or the page.
    var shareURL: URL? { url ?? link?.url }

    /// The history's dedupe key: one item per path, and one per page.
    var key: String { Self.key(path: path, link: link?.url) }

    static func key(path: String?, link: URL?) -> String {
        if let path { return "file:" + path }
        return "link:" + (link?.absoluteString ?? "")
    }

    var contentType: UTType? { contentTypeIdentifier.flatMap(UTType.init) }

    /// The file name extension, uppercased, as the icon band shows it. Empty for folders and apps.
    var fileExtension: String {
        guard let path, kind != .folder, kind != .app else { return "" }
        return (path as NSString).pathExtension.uppercased()
    }

    /// The containing folder's name, for the event line ("· Downloads").
    var folderName: String? {
        guard let path else { return nil }
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? nil : FileManager.default.displayName(atPath: parent)
    }

    /// The download page's host without `www.`, for "Downloaded from billing.example.com".
    var sourceHost: String? {
        guard let host = sourcePage?.host(percentEncoded: false) else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Whether the item lies inside `folder` (a standardized absolute path), at any depth.
    func isInside(_ folder: String) -> Bool {
        guard let path else { return false }
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return path.hasPrefix(prefix)
    }
}

/// One thing a source observed, before the history merges it into an item.
nonisolated struct FlixActivityEvent: Sendable, Equatable {
    var path: String?
    var link: FlixLink?
    var name: String
    var kind: FlixItemKind
    var activity: FlixActivity
    var date: Date
    var sourcePage: URL?
    var contentTypeIdentifier: String?
    var byteSize: Int64?
    var bundleIdentifier: String?

    init(path: String? = nil, link: FlixLink? = nil, name: String, kind: FlixItemKind, activity: FlixActivity,
         date: Date, sourcePage: URL? = nil, contentTypeIdentifier: String? = nil, byteSize: Int64? = nil,
         bundleIdentifier: String? = nil) {
        self.path = path.map(FlixPaths.standardized)
        self.link = link
        self.name = name
        self.kind = kind
        self.activity = activity
        self.date = date
        self.sourcePage = sourcePage
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteSize = byteSize
        self.bundleIdentifier = bundleIdentifier
    }

    var key: String { FlixItem.key(path: path, link: link?.url) }
}
