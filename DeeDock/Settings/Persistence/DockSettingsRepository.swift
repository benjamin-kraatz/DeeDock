import Foundation

/// Persists configuration independently of pins. Reading never writes or repairs saved bytes.
struct DockSettingsRepository {
    private let defaults: UserDefaults
    private let key = "dock.settings.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Returns defaults for an absent key; throws for unreadable data or invalid numeric values.
    func load() throws -> DockSettings {
        guard let object = defaults.object(forKey: key) else { return .defaults }
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
