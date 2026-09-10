import Foundation

/// Stores the shared pin-weather document. One map for the whole app, not per display.
nonisolated struct PinWeatherRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "dock.pin-weather.v1") {
        self.defaults = defaults
        self.key = key
    }

    /// Returns nil when nothing has been stored yet. Throws rather than reporting empty
    /// weather, so unreadable bytes are not mistaken for a fresh document.
    func load() throws -> PinWeatherDocument? {
        guard let object = defaults.object(forKey: key) else { return nil }
        guard let data = object as? Data, data.count <= PinWeatherLimits.maximumEncodedBytes else {
            throw CocoaError(.coderReadCorrupt)
        }
        let document = try JSONDecoder().decode(PinWeatherDocument.self, from: data)
        guard document.isValid else { throw CocoaError(.coderReadCorrupt) }
        return document
    }

    /// Refuses an invalid document so a failed load cannot be followed by a write that
    /// destroys the evidence still sitting in storage.
    func save(_ document: PinWeatherDocument) throws {
        guard document.isValid else { throw CocoaError(.coderInvalidValue) }
        let data = try JSONEncoder().encode(document)
        guard data.count <= PinWeatherLimits.maximumEncodedBytes else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        defaults.set(data, forKey: key)
    }

    func remove() {
        defaults.removeObject(forKey: key)
    }
}
