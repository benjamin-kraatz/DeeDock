import Foundation

/// What Flix Pick learned on this Mac: which files and folders were picked in each app's Open and
/// Save pickers, and how often.
///
/// Stored inside drag memory (`FlixDragMemory.picks`, in `memory.json`), so Settings' **Forget**
/// empties it with the rest, and recorded only while **Learn where I drag things** is on. Keys are
/// bundle identifiers, then standardized paths. Capped at ``pathsPerApp`` paths per app (the least
/// recently picked goes first) and ``appLimit`` apps (the app whose picker was used longest ago goes
/// first), so the file stays small. Pure value type.
nonisolated struct FlixPickMemory: Codable, Equatable, Sendable {
    /// One picked path in one app.
    nonisolated struct Entry: Codable, Equatable, Sendable {
        var count: Int
        var last: Date
        /// Picked in a Save picker (a folder) rather than an Open picker (a file).
        var isFolder: Bool
    }

    /// One app's picks.
    nonisolated struct App: Codable, Equatable, Sendable {
        var picks: [String: Entry] = [:]
        var lastUsed: Date
    }

    static let pathsPerApp = 40
    static let appLimit = 60

    var apps: [String: App] = [:]

    init() {}

    /// The paths picked in `app`'s pickers.
    func picks(for app: String) -> [String: Entry] { apps[app]?.picks ?? [:] }

    /// Counts a pick of `path` in `app`'s picker at `date`, evicting the oldest entries past the caps.
    mutating func record(_ path: String, isFolder: Bool, app: String, at date: Date) {
        let path = FlixPaths.standardized(path)
        var entry = apps[app] ?? App(lastUsed: date)
        var pick = entry.picks[path] ?? Entry(count: 0, last: date, isFolder: isFolder)
        pick.count += 1
        pick.last = max(pick.last, date)
        pick.isFolder = isFolder
        entry.picks[path] = pick
        entry.lastUsed = max(entry.lastUsed, date)
        while entry.picks.count > Self.pathsPerApp,
              let oldest = entry.picks.min(by: { $0.value.last < $1.value.last })?.key {
            entry.picks[oldest] = nil
        }
        apps[app] = entry
        while apps.count > Self.appLimit, let oldest = apps.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
            apps[oldest] = nil
        }
    }

    /// Forgets `path` in `app`, for a file that is gone.
    mutating func forget(_ path: String, app: String) {
        apps[app]?.picks[FlixPaths.standardized(path)] = nil
        if apps[app]?.picks.isEmpty == true { apps[app] = nil }
    }
}
