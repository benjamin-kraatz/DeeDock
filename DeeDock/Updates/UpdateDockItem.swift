import Foundation

/// Snapshot of the dock's temporary update tile, shared by every display dock.
///
/// Compiled into every target because the dock's slot model names it. Only the directly
/// distributed build ever produces one.
struct UpdateDockItem: Identifiable, Equatable {
    enum State: Equatable {
        /// An offer that needs the user to download or approve it.
        case available
        /// A downloaded offer that only needs a restart.
        case ready
        /// An automatic install finished; the tile opens the changelog.
        case installed
    }

    let state: State
    /// The offered version, or the running version once installed.
    let version: String
    var id: String { "system-update" }

    var title: LocalizedStringResource {
        switch state {
        case .available: .updatesAwarenessTitle
        case .ready: .updatesReadyCalloutTitle
        case .installed: .updatesInstalledCalloutTitle
        }
    }

    var symbol: String {
        switch state {
        case .available: "arrow.down"
        case .ready: "arrow.clockwise"
        case .installed: "sparkles"
        }
    }
}
