import Foundation

/// Persists configuration independently of pins. Reading never writes or repairs saved bytes.
struct DockSettingsRepository {
    private let defaults: UserDefaults
    private let key = "dock.settings.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Whether a settings document is saved, readable or not.
    var hasSavedDocument: Bool { defaults.object(forKey: key) != nil }

    /// Returns defaults for an absent key; throws for unreadable data or invalid numeric values.
    ///
    /// The defaults depend on whether DOKK ran on this Mac before: an earlier launch gets
    /// ``DockSettings/earlierInstallDefaults``. Every launch that sees a display writes the display
    /// profiles document, and the tour writes its record, both after settings load, so either key
    /// means an earlier launch. `AnalyticsConsentStore.hasEarlierLaunch` reads the same evidence.
    func load() throws -> DockSettings {
        guard let object = defaults.object(forKey: key) else {
            let earlier = ["dock.displays.v1", "onboarding.v1"].contains { defaults.object(forKey: $0) != nil }
            return earlier ? .earlierInstallDefaults : .defaults
        }
        guard let data = object as? Data else { throw CocoaError(.coderReadCorrupt) }
        let settings = try JSONDecoder().decode(DockSettings.self, from: data)
        guard let normalized = settings.normalized else { throw CocoaError(.coderReadCorrupt) }
        return normalized
    }

    /// Validates and encodes before replacing the settings key; never touches favorites.
    func save(_ settings: DockSettings) throws {
        guard let normalized = settings.normalized else { throw CocoaError(.coderInvalidValue) }
        defaults.set(try JSONEncoder().encode(normalized), forKey: key)
    }
}
