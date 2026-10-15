import Foundation

/// Reads and writes `LookoutSettings` as JSON under `hub.lookout.v1` in the injected defaults. Tests and previews pass
/// a throwaway suite; the test host must never use `.standard`, which is DOKK's own domain.
nonisolated struct LookoutSettingsRepository: Sendable {
    static let key = "hub.lookout.v1"

    // UserDefaults is thread-safe; it isn't marked Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The saved settings, or the defaults (Lookout off) when none are saved. Reading never writes or repairs saved
    /// bytes.
    ///
    /// - Throws: Saved data that isn't `Data` or doesn't decode.
    func load() throws -> LookoutSettings {
        guard let object = defaults.object(forKey: Self.key) else { return LookoutSettings() }
        guard let data = object as? Data else { throw CocoaError(.coderReadCorrupt) }
        return try JSONDecoder().decode(LookoutSettings.self, from: data)
    }

    /// The saved settings, or the defaults when they're missing or unreadable (Lookout stays off then).
    func loadOrDefault() -> LookoutSettings {
        (try? load()) ?? LookoutSettings()
    }

    /// Replaces the saved settings.
    ///
    /// - Throws: Encoding errors.
    func save(_ settings: LookoutSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        defaults.set(try encoder.encode(settings), forKey: Self.key)
    }
}
