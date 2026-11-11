import CoreGraphics
import Foundation
import Observation

/// Where the orb sits on one display, as a fraction of that display's visible frame.
///
/// Relative positions survive resolution and arrangement changes; the geometry clamps the orb
/// back inside the visible frame when the display shrinks.
nonisolated struct VaporOrbPlacement: Codable, Equatable, Sendable {
    /// 0 at the visible frame's left edge, 1 at its right edge, for the orb's centre.
    var x: Double
    /// 0 at the visible frame's bottom edge, 1 at its top edge (AppKit's y-up convention).
    var y: Double
}

/// Everything Vapor keeps across launches.
nonisolated struct VaporPersistedState: Codable, Equatable, Sendable {
    var isEnabled = false
    /// The display identity (`DisplaySnapshot.id`) the orb was last placed on.
    var displayID: String?
    /// One placement per display identity, never per screen index.
    var placements: [String: VaporOrbPlacement] = [:]
    /// Paths of the folders in the orb, in the order they were added.
    var folderPaths: [String] = []
}

/// Persists Vapor's on/off state, orb placements and folders in user defaults.
///
/// Turning Vapor off keeps the folders and placements, so turning it on again brings them back.
@MainActor @Observable
final class VaporStore {
    private(set) var state: VaporPersistedState
    @ObservationIgnored private let defaults: UserDefaults?
    private static let key = "vapor.state.v1"

    /// Passing nil creates an inert store for previews and tests that never reads or writes preferences.
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        state = defaults?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(VaporPersistedState.self, from: $0) }
            ?? VaporPersistedState()
    }

    var isEnabled: Bool { state.isEnabled }

    func setEnabled(_ enabled: Bool) { update { $0.isEnabled = enabled } }

    func setFolders(_ urls: [URL]) { update { $0.folderPaths = urls.map(\.path) } }

    /// Records the orb's position on `displayID` and makes that display the current one.
    func setPlacement(_ placement: VaporOrbPlacement, displayID: String) {
        update {
            $0.placements[displayID] = placement
            $0.displayID = displayID
        }
    }

    private func update(_ change: (inout VaporPersistedState) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        state = next
        if let data = try? JSONEncoder().encode(next) { defaults?.set(data, forKey: Self.key) }
    }
}
