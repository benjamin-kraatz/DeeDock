import Foundation

/// Reads and writes `FlixSettings` as JSON under `flix.settings.v1` in the injected defaults. Tests
/// and previews pass a throwaway suite; the test host must never use `.standard`.
nonisolated struct FlixSettingsRepository: Sendable {
    static let key = "flix.settings.v1"

    // UserDefaults is thread-safe; it isn't marked Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The saved settings, or the defaults when none are saved.
    ///
    /// - Throws: Saved data that isn't `Data` or doesn't decode.
    func load() throws -> FlixSettings {
        guard let object = defaults.object(forKey: Self.key) else { return FlixSettings() }
        guard let data = object as? Data else { throw CocoaError(.coderReadCorrupt) }
        return try JSONDecoder().decode(FlixSettings.self, from: data)
    }

    func loadOrDefault() -> FlixSettings { (try? load()) ?? FlixSettings() }

    func save(_ settings: FlixSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        defaults.set(try encoder.encode(settings), forKey: Self.key)
    }
}
