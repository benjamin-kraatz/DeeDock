import Foundation

/// Persists configuration independently of pins. Reading never writes or repairs the settings
/// document; the first load records Radar's tile default under its own key.
struct DockSettingsRepository {
    private let defaults: UserDefaults
    private let key = "dock.settings.v1"
    private let harborTileKey = "harbor.tileDefault.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Returns defaults for an absent key; throws for unreadable data or invalid numeric values.
    /// An untouched `showHarborTile` takes ``harborTileDefault()``; an explicit value wins.
    func load() throws -> DockSettings {
        let harborTile = harborTileDefault()
        guard let object = defaults.object(forKey: key) else {
            var settings = DockSettings.defaults
            settings.showHarborTile = harborTile
            return settings
        }
        guard let data = object as? Data else { throw CocoaError(.coderReadCorrupt) }
        let decoder = JSONDecoder()
        decoder.userInfo[DockSettings.harborTileDefaultKey] = harborTile
        let settings = try decoder.decode(DockSettings.self, from: data)
        guard let normalized = settings.normalized else { throw CocoaError(.coderReadCorrupt) }
        return normalized
    }

    /// Whether Radar's tile is on for this install while the person has not set it, decided once
    /// and recorded so later launches and later default changes cannot move it.
    ///
    /// Only this decision is pinned; every other setting keeps following the current defaults.
    /// The first call on a fresh install records on. A Mac that ran an earlier DOKK records off:
    /// a settings document means an edit, and every launch that sees a display writes the display
    /// profiles document, as the tour writes its record, both after settings load.
    /// `AnalyticsConsentStore.hasEarlierLaunch` reads the same evidence.
    func harborTileDefault() -> Bool {
        if let recorded = defaults.object(forKey: harborTileKey) as? Bool { return recorded }
        let earlier = [key, "dock.displays.v1", "onboarding.v1"].contains { defaults.object(forKey: $0) != nil }
        defaults.set(!earlier, forKey: harborTileKey)
        return !earlier
    }

    /// Validates and encodes before replacing the settings key; never touches favorites.
    func save(_ settings: DockSettings) throws {
        guard let normalized = settings.normalized else { throw CocoaError(.coderInvalidValue) }
        defaults.set(try JSONEncoder().encode(normalized), forKey: key)
    }
}
