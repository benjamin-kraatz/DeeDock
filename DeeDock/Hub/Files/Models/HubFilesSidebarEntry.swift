import Foundation

/// One row of the sidebar's Favorites list: a built-in place or a folder someone added.
///
/// Both kinds share one ordered list, so people can mix them freely and remove built-in places
/// as in Finder. Settings → Hub and the Favorites header's menu bring removed places back.
nonisolated enum HubFilesSidebarEntry: Hashable, Sendable, Identifiable {
    case place(HubFilesPlace)
    case folder(HubFilesSidebarFolder)

    var id: HubFilesSidebarEntryID {
        switch self {
        case .place(let place): .place(place)
        case .folder(let folder): .folder(folder.id)
        }
    }

    /// The built-in places in their default order, the list a first launch shows.
    static var defaults: [HubFilesSidebarEntry] { HubFilesPlace.allCases.map(Self.place) }
}

/// Stable identity of a Favorites row. Places are unique, so the place itself is the identity;
/// an added folder keeps its UUID across renames and moves.
nonisolated enum HubFilesSidebarEntryID: Hashable, Sendable {
    case place(HubFilesPlace)
    case folder(UUID)
}

/// A folder added to the sidebar.
///
/// `bookmark` follows the folder through renames and moves. `path` is where it was last found,
/// the fallback when the bookmark can't be resolved and the name shown while it is missing.
nonisolated struct HubFilesSidebarFolder: Hashable, Sendable, Codable, Identifiable {
    let id: UUID
    var path: String
    var bookmark: Data?

    init(id: UUID = UUID(), path: String, bookmark: Data? = nil) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
    }

    var url: URL { URL(filePath: path, directoryHint: .notDirectory) }
}

/// What resolving an added folder found. Computed off the main actor by a
/// `HubFilesSidebarResolving`; the store keeps the latest one per folder.
nonisolated struct HubFilesSidebarResolution: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// The folder exists at `url`.
        case available
        /// Deleted, in the Trash, or its bookmark no longer resolves on a mounted volume.
        case missing
        /// It lives on a volume that isn't mounted. It comes back when the volume mounts.
        case disconnected(volume: String)
    }

    var status: Status
    /// Where the folder is now, or where it was last seen.
    var url: URL
    /// The folder's display name (localized for system folders, as Finder shows it).
    var name: String
    /// The enclosing folder's display name, the subtitle that tells two same-named folders apart.
    var parentName: String
    /// Fresh bookmark data when the stored one was missing or stale; nil keeps the stored one.
    var refreshedBookmark: Data?
}

/// The persisted Favorites list under ``defaultsKey``.
///
/// Places are stored by raw value, so a place a future build removes is dropped instead of
/// failing the whole list. A missing or unreadable value yields the default places.
nonisolated struct HubFilesSidebarSnapshot: Codable, Equatable {
    static let defaultsKey = "hub.files.sidebar.v1"

    enum Item: Codable, Equatable {
        case place(String)
        case folder(HubFilesSidebarFolder)
    }

    var items: [Item]

    init(entries: [HubFilesSidebarEntry]) {
        items = entries.map { entry in
            switch entry {
            case .place(let place): .place(place.rawValue)
            case .folder(let folder): .folder(folder)
            }
        }
    }

    /// The entries this snapshot describes, skipping unknown places and duplicates.
    var entries: [HubFilesSidebarEntry] {
        var seen = Set<HubFilesSidebarEntryID>()
        return items.compactMap { item -> HubFilesSidebarEntry? in
            let entry: HubFilesSidebarEntry? = switch item {
            case .place(let raw): HubFilesPlace(rawValue: raw).map(HubFilesSidebarEntry.place)
            case .folder(let folder): .folder(folder)
            }
            guard let entry, seen.insert(entry.id).inserted else { return nil }
            return entry
        }
    }

    static func load(from defaults: UserDefaults) -> [HubFilesSidebarEntry] {
        guard let data = defaults.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(HubFilesSidebarSnapshot.self, from: data) else {
            return HubFilesSidebarEntry.defaults
        }
        return snapshot.entries
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
