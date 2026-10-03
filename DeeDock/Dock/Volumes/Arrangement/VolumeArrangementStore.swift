import Foundation
import Observation

/// Persists the drive arrangement and shares it between the docks and Settings.
///
/// The dock context menu, dock drags, and the Settings list all edit this one store, so a drive
/// hidden or moved anywhere updates everywhere.
@MainActor @Observable
final class VolumeArrangementStore {
    private(set) var arrangement: VolumeArrangement
    /// Called after a user edit (hide, show, move, forget). `remember` does not call it, because
    /// the volume controller calls `remember` while it is already publishing.
    @ObservationIgnored var didChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "dock.volume-arrangement.v1"

    private struct Document: Codable {
        var version = 1
        var arrangement: VolumeArrangement
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // An unreadable document starts over. The arrangement only holds order and hidden flags,
        // and every drive shows again rather than staying hidden by mistake.
        if let data = defaults.data(forKey: Self.key),
           let document = try? JSONDecoder().decode(Document.self, from: data), document.version == 1 {
            arrangement = document.arrangement
        } else {
            arrangement = VolumeArrangement()
        }
    }

    #if DEBUG
    /// A store for previews that starts from `arrangement` and never touches the real defaults.
    convenience init(previewing arrangement: VolumeArrangement) {
        self.init(defaults: UserDefaults(suiteName: "VolumeArrangementPreview") ?? .standard)
        self.arrangement = arrangement
    }
    #endif

    var entries: [VolumeArrangementEntry] { arrangement.entries }

    func isHidden(_ volumeID: String) -> Bool { arrangement.isHidden(volumeID) }

    /// Records mounted volumes. Saves only when something changed.
    func remember(_ volumes: [VolumeInfo], previouslyMounted: Set<String>) {
        var next = arrangement
        next.remember(volumes, previouslyMounted: previouslyMounted, at: Date())
        guard next != arrangement else { return }
        arrangement = next
        save()
    }

    func setHidden(_ volumeID: String, _ hidden: Bool) {
        edit { $0.setHidden(volumeID, hidden) }
    }

    func forget(_ volumeID: String) {
        edit { $0.forget(volumeID) }
    }

    /// See `VolumeArrangement.move(_:to:within:)`.
    func move(_ volumeID: String, to index: Int, within sequence: [String]) {
        edit { $0.move(volumeID, to: index, within: sequence) }
    }

    private func edit(_ change: (inout VolumeArrangement) -> Void) {
        var next = arrangement
        change(&next)
        guard next != arrangement else { return }
        arrangement = next
        save()
        didChange?()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Document(arrangement: arrangement)) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
