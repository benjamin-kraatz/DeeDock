import Foundation

/// Stores named watch configurations for the whole app. Capture pixels and window IDs are never written.
nonisolated struct WindowWatchPresetRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "dock.window-watch-presets.v1") {
        self.defaults = defaults
        self.key = key
    }

    /// Returns nil when nothing has been stored. Throws rather than reporting an empty list,
    /// so unreadable bytes are surfaced instead of looking like the user deleted every preset.
    func load() throws -> WindowWatchPresetDocument? {
        guard let object = defaults.object(forKey: key) else { return nil }
        guard let data = object as? Data else { throw CocoaError(.coderReadCorrupt) }
        let document = try JSONDecoder().decode(WindowWatchPresetDocument.self, from: data)
        guard document.isValid else { throw CocoaError(.coderReadCorrupt) }
        return document
    }

    /// Refuses an invalid document so a failed load can never be followed by a write that
    /// destroys the evidence still sitting in storage.
    func save(_ document: WindowWatchPresetDocument) throws {
        guard document.isValid else { throw CocoaError(.coderInvalidValue) }
        defaults.set(try JSONEncoder().encode(document), forKey: key)
    }
}
