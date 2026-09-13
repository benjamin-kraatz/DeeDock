import Foundation
import Observation

/// App-wide favorite identities, independent of display pins and launch history.
@MainActor @Observable
final class LauncherFavorites {
    private(set) var ids: Set<String>
    @ObservationIgnored private let defaults: UserDefaults?
    private static let key = "launcher.favorites.v1"

    /// Pass nil for previews to avoid reading or changing real preferences.
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        ids = Set(defaults?.stringArray(forKey: Self.key) ?? [])
    }

    /// Persists an explicit favorite change for the catalog's stable application identity.
    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) }
        else { ids.insert(id) }
        defaults?.set(ids.sorted(), forKey: Self.key)
    }
}
