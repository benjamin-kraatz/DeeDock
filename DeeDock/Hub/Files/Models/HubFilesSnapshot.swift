import Foundation

/// The persisted shape of the Files tab under `hub.files.v1`.
///
/// Stores only layout and locations; selections, history, and listings are rebuilt on launch.
nonisolated struct HubFilesSnapshot: Codable, Equatable, Sendable {
    /// One pane's persisted state.
    struct Pane: Codable, Equatable, Sendable {
        var location: HubFilesLocation
        var sort: HubFileSort
    }

    /// One browser tab's persisted state.
    struct Tab: Codable, Equatable, Sendable {
        /// One or two panes. The second survives while split is off so toggling restores it.
        var panes: [Pane]
        var isSplit: Bool
        var activePane: Int
        var viewMode: HubFilesViewMode
    }

    var tabs: [Tab]
    var selectedTab: Int
    var showsPreview: Bool

    /// The `UserDefaults` key.
    static let defaultsKey = "hub.files.v1"

    /// The first-run layout from the mockup: Documents | Downloads split in list view, then a
    /// Downloads tab in icon view.
    static func firstRun(home: URL) -> HubFilesSnapshot {
        let documents = HubFilesPlace.documents.location(home: home)
        let downloads = HubFilesPlace.downloads.location(home: home)
        return HubFilesSnapshot(
            tabs: [
                Tab(panes: [Pane(location: documents, sort: HubFileSort()), Pane(location: downloads, sort: HubFileSort())],
                    isSplit: true, activePane: 0, viewMode: .list),
                Tab(panes: [Pane(location: downloads, sort: HubFileSort())], isSplit: false, activePane: 0, viewMode: .icons)
            ],
            selectedTab: 0,
            showsPreview: true)
    }

    /// Reads the snapshot, or nil when absent or unreadable.
    static func load(from defaults: UserDefaults) -> HubFilesSnapshot? {
        guard let data = defaults.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(HubFilesSnapshot.self, from: data),
              !snapshot.tabs.isEmpty else { return nil }
        return snapshot
    }

    /// Writes the snapshot.
    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
