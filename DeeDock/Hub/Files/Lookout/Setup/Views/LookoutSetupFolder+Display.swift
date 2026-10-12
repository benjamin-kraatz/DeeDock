import Foundation

extension LookoutSetupFolder {
    /// The row's name: the suggested folders by their localized names (Schreibtisch, Dokumente…), others by their
    /// folder name.
    var displayName: String {
        switch suggestion {
        case .desktop?: String(localized: .lookoutFolderDesktop)
        case .documents?: String(localized: .lookoutFolderDocuments)
        case .downloads?: String(localized: .lookoutFolderDownloads)
        case .pictures?: String(localized: .lookoutFolderPictures)
        case nil: (path as NSString).lastPathComponent
        }
    }

    /// The path under the name, with `~` for the home folder ("~/Desktop").
    func tildePath(home: String) -> String {
        Self.tildePath(path, home: home)
    }

    /// `path` with `~` for `home`, without reading the disk.
    static func tildePath(_ path: String, home: String) -> String {
        if path == home { return "~" }
        let prefix = home.hasSuffix("/") ? home : home + "/"
        return path.hasPrefix(prefix) ? "~/" + path.dropFirst(prefix.count) : path
    }

    /// The name a folder at `path` shows: a suggested folder's localized name, or its own.
    static func displayName(of path: String, home: String) -> String {
        LookoutFolderChoice.suggestions(home: home).first { $0.path == path }?.displayName
            ?? (path as NSString).lastPathComponent
    }
}
