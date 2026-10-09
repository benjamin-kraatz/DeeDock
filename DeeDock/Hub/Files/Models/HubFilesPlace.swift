import Foundation

/// A Favorites entry in the Files sidebar.
nonisolated enum HubFilesPlace: String, CaseIterable, Identifiable, Sendable {
    case recents, desktop, documents, downloads, home, applications

    var id: Self { self }

    /// SF Symbol drawn in the accent color, matching the mockup's line glyphs.
    var symbolName: String {
        switch self {
        case .recents: "clock"
        case .desktop: "menubar.dock.rectangle"
        case .documents: "doc"
        case .downloads: "arrow.down.circle"
        case .home: "house"
        case .applications: "square.grid.2x2"
        }
    }

    /// The place's folder for the given home folder, or nil for Recents.
    ///
    /// For the signed-in user's real home, Desktop, Documents, Downloads, and Applications come from
    /// `FileManager`'s standard-directory lookup, so a relocated folder (for example a Documents
    /// folder that is a symlink elsewhere, or a redirected container) is found where macOS says it
    /// is. Any other `home` (previews and tests use an in-memory one) keeps the conventional
    /// home-relative paths, so those never touch the real file system.
    func url(home: URL) -> URL? {
        switch self {
        case .recents: return nil
        case .home: return HubFilesPath.normalized(home)
        case .desktop, .documents, .downloads, .applications: break
        }
        if HubFilesPath.same(home, Self.systemHome), let system = Self.systemFolders[self] { return system }
        switch self {
        case .desktop: return home.appending(path: "Desktop", directoryHint: .notDirectory)
        case .documents: return home.appending(path: "Documents", directoryHint: .notDirectory)
        case .downloads: return home.appending(path: "Downloads", directoryHint: .notDirectory)
        default: return URL(filePath: "/Applications", directoryHint: .notDirectory)
        }
    }

    /// The real home folder, normalized like the live data source's.
    private static let systemHome = HubFilesPath.normalized(FileManager.default.homeDirectoryForCurrentUser)

    /// Standard folders as macOS reports them, resolved once per launch.
    private static let systemFolders: [HubFilesPlace: URL] = {
        let lookups: [(HubFilesPlace, FileManager.SearchPathDirectory, FileManager.SearchPathDomainMask)] = [
            (.desktop, .desktopDirectory, .userDomainMask),
            (.documents, .documentDirectory, .userDomainMask),
            (.downloads, .downloadsDirectory, .userDomainMask),
            (.applications, .applicationDirectory, .localDomainMask),
        ]
        var folders: [HubFilesPlace: URL] = [:]
        for (place, directory, domain) in lookups {
            if let url = FileManager.default.urls(for: directory, in: domain).first {
                folders[place] = HubFilesPath.normalized(url)
            }
        }
        return folders
    }()

    /// The location this place opens.
    func location(home: URL) -> HubFilesLocation {
        url(home: home).map(HubFilesLocation.folder(normalizing:)) ?? .recents
    }

    /// Folder URLs of every place except Recents; breadcrumb and column anchors.
    static func anchors(home: URL) -> [URL] {
        allCases.compactMap { $0.url(home: home) }
    }

    /// The place whose folder is `url`, if any.
    static func place(for url: URL, home: URL) -> HubFilesPlace? {
        allCases.first { place in place.url(home: home).map { HubFilesPath.same($0, url) } ?? false }
    }
}
