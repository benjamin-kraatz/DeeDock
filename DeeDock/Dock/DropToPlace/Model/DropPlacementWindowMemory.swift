import CoreGraphics
import Foundation

/// One app's last known window frame. This is everything Drop to Place stores about a window:
/// no title, no contents, no window identity.
nonisolated struct DropPlacementMemoryEntry: Codable, Equatable, Sendable {
    /// Global AppKit coordinates, in points.
    var frame: CGRect
    /// The persistent display identity from `DisplaySnapshot.id`, never a screen index.
    var displayID: String
    var date: Date
}

/// Remembers where each app's window last was, keyed by bundle identifier, in local defaults.
///
/// Written when a placement succeeds and when an app deactivates or hides (see
/// `DropPlacementWindowRecorder`). Read once when a drag starts. Nothing leaves the Mac.
@MainActor
final class DropPlacementWindowMemory {
    /// Older entries are dropped beyond this count, so the store cannot grow without bound.
    static let capacity = 200
    private static let key = "dropToPlace.windowMemory.v1"
    private let defaults: UserDefaults?
    private var entries: [String: DropPlacementMemoryEntry]

    /// - Parameter defaults: Nil keeps everything in memory, for previews and tests.
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: DropPlacementMemoryEntry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    func entry(for bundleIdentifier: String) -> DropPlacementMemoryEntry? { entries[bundleIdentifier] }

    /// Saves `frame` for the app. Degenerate frames are ignored.
    func record(_ frame: CGRect, displayID: String, for bundleIdentifier: String, at date: Date = Date()) {
        guard frame.width >= 1, frame.height >= 1, frame.minX.isFinite, frame.minY.isFinite else { return }
        let entry = DropPlacementMemoryEntry(frame: frame.integral, displayID: displayID, date: date)
        guard entries[bundleIdentifier] != entry else { return }
        entries[bundleIdentifier] = entry
        if entries.count > Self.capacity {
            let oldest = entries.sorted { $0.value.date < $1.value.date }.prefix(entries.count - Self.capacity)
            for (key, _) in oldest { entries[key] = nil }
        }
        guard let defaults, let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
