import Foundation

/// What a tile's running indicator shows.
///
/// `background` is macOS 27's "Running in Background": the app's main process has quit, but
/// processes it started keep running. The indicator keeps its geometry and turns muted, as in
/// the system Dock. A tile is in exactly one state, so a regular running instance always wins.
enum DockRunningState: Hashable {
    case notRunning
    /// At least one regular application process is running.
    case running
    /// Only processes the app left behind are running. See `BackgroundApplicationMonitor`.
    case background

    /// Maps a plain running flag, for tiles that have no background state.
    init(running: Bool) {
        self = running ? .running : .notRunning
    }

    /// Whether the tile draws an indicator at all, muted or not.
    var showsIndicator: Bool { self != .notRunning }
}

extension DockItem {
    /// The indicator state for this tile. `isRunning` wins if both flags are ever set.
    var runningState: DockRunningState {
        isRunning ? .running : (isRunningInBackground ? .background : .notRunning)
    }
}
