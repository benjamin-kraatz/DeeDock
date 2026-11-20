import Foundation
import Observation

/// The live Flix Files settings. Saves on every change and tells the coordinator, which restarts
/// only the parts that changed.
///
/// Phase B reads the intelligence and link switches from ``settings`` (for example
/// `settings.tracksLinks`, `settings.suggestsForFrontWindow`) and observes ``changed`` or the
/// `@Observable` property itself.
@MainActor @Observable
final class FlixSettingsStore {
    var settings: FlixSettings {
        didSet {
            guard settings != oldValue else { return }
            try? repository?.save(settings)
            changed?(oldValue, settings)
        }
    }
    /// Called after a change with the old and new values.
    @ObservationIgnored var changed: ((FlixSettings, FlixSettings) -> Void)?
    @ObservationIgnored private let repository: FlixSettingsRepository?

    /// Passing nil keeps settings in memory, for previews.
    init(repository: FlixSettingsRepository?) {
        self.repository = repository
        settings = repository?.loadOrDefault() ?? FlixSettings()
    }

    /// Updates one watched folder's access without rewriting the list's order.
    func setAccess(_ access: FlixFolderAccessState, for path: String) {
        guard let index = settings.watchedFolders.firstIndex(where: { $0.path == path }),
              settings.watchedFolders[index].access != access else { return }
        settings.watchedFolders[index].access = access
    }

    func addWatchedFolder(_ path: String, access: FlixFolderAccessState) {
        let path = FlixPaths.standardized(path)
        if let index = settings.watchedFolders.firstIndex(where: { $0.path == path }) {
            settings.watchedFolders[index].isEnabled = true
            settings.watchedFolders[index].access = access
        } else {
            settings.watchedFolders.append(FlixWatchedFolder(path: path, access: access))
        }
    }

    func removeWatchedFolder(_ path: String) {
        settings.watchedFolders.removeAll { $0.path == path }
    }
}
