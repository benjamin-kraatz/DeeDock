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
    /// The page a download came from (`kMDItemWhereFroms`), cleaned by `FlixURLSanitizer`. Kept
    /// only while web links are on, the site is not excluded (``FlixSourcePolicy``), and the
    /// download's window was verified as a normal one (``sourcePageIsVerified``). Set only through
    /// `FlixHistoryDocument.attachVerifiedSource(_:toPath:)`; source events never store it.
    var sourcePage: URL?
    /// True when ``sourcePage`` was stored after the link tracker verified the download came from
    /// a normal (not private) browser window showing that very page. A stored page without it
    /// (saved by an earlier version) is stripped to its host (``FlixSourcePolicy``).
    var sourcePageIsVerified: Bool?
    /// The download page's host without `www.`, for "Downloaded from billing.example.com". Kept
    /// when the page itself is not (web links off); nil for an excluded site.
    var sourceHost: String?
    /// The uniform type identifier, when known.
    var contentTypeIdentifier: String?
    var byteSize: Int64?
    /// Flagged items never age out of the history.
    var isFlagged: Bool
    /// Set for apps, so reopening and icons do not depend on the path.
    var bundleIdentifier: String?
    /// Which file the row lists: recorded with the event that saw it, or captured in the background
    /// soon after. Destructive commands act only while the file at ``path`` still matches
    /// (``FlixFileOperations/check(_:)``). Nil for links and for rows not checked yet.
    var fileIdentity: FlixFileIdentity?

    /// - Parameter sourceHost: Defaults to `sourcePage`'s host.
    init(id: UUID = UUID(), path: String? = nil, link: FlixLink? = nil, name: String, kind: FlixItemKind,
         activity: FlixActivity, date: Date, firstSeen: Date? = nil, sourcePage: URL? = nil, sourceHost: String? = nil,
         contentTypeIdentifier: String? = nil, byteSize: Int64? = nil, isFlagged: Bool = false,
         bundleIdentifier: String? = nil, fileIdentity: FlixFileIdentity? = nil) {
        self.id = id
        self.path = path
        self.link = link
        self.name = name
        self.kind = kind
        self.activity = activity
        self.date = date
        self.firstSeen = firstSeen ?? date
        self.sourcePage = sourcePage
        self.sourceHost = sourceHost ?? sourcePage.flatMap(FlixPaths.displayHost)
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteSize = byteSize
        self.isFlagged = isFlagged
        self.bundleIdentifier = bundleIdentifier
        self.fileIdentity = fileIdentity
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

    /// The containing folder's name, for the event line ("· Downloads"). From the path alone
    /// (``FlixFolderNames``), so drawing a row never reads the disk.
    var folderName: String? {
        guard let path else { return nil }
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? nil : FlixFolderNames.displayName(of: parent)
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
    /// The download page as the source read it. The history never stores it from an event: only
    /// the link tracker's verified check attaches a page to a file (``FlixItem/sourcePageIsVerified``).
    /// ``FlixSourcePolicy`` decides what of it the tracker may look at.
    var sourcePage: URL?
    var sourceHost: String?
    var contentTypeIdentifier: String?
    var byteSize: Int64?
    var bundleIdentifier: String?
    /// The file as the source saw it, when the source read it from disk (the folder watcher).
    var fileIdentity: FlixFileIdentity?
    /// The download page exactly as `kMDItemWhereFroms` named it, query included, before cleaning.
    /// In memory only: the link tracker compares it with the address the browser shows, so two pages
    /// that differ only in what cleaning removes (`?id=1`, `?id=2`) never vouch for each other. It
    /// is never stored, and ``FlixSourcePolicy`` drops it with ``sourcePage``.
    var sourcePageIdentity: URL?

    /// - Parameter sourceHost: Defaults to `sourcePage`'s host.
    init(path: String? = nil, link: FlixLink? = nil, name: String, kind: FlixItemKind, activity: FlixActivity,
         date: Date, sourcePage: URL? = nil, sourcePageIdentity: URL? = nil, sourceHost: String? = nil,
         contentTypeIdentifier: String? = nil, byteSize: Int64? = nil, bundleIdentifier: String? = nil,
         fileIdentity: FlixFileIdentity? = nil) {
        self.path = path.map(FlixPaths.standardized)
        self.link = link
        self.name = name
        self.kind = kind
        self.activity = activity
        self.date = date
        self.sourcePage = sourcePage
        self.sourceHost = sourceHost ?? sourcePage.flatMap(FlixPaths.displayHost)
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteSize = byteSize
        self.bundleIdentifier = bundleIdentifier
        self.fileIdentity = fileIdentity
        self.sourcePageIdentity = sourcePage == nil ? nil : sourcePageIdentity
    }

    var key: String { FlixItem.key(path: path, link: link?.url) }
}
