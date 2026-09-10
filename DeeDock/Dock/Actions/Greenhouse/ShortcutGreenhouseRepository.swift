import Foundation

/// Stores the app-wide greenhouse opt-in. One preference for every display.
///
/// UserDefaults only. This type never opens a network session or a file outside the suite.
nonisolated struct ShortcutGreenhouseRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = ShortcutGreenhouseLimits.storageKey) {
        self.defaults = defaults
        self.key = key
    }

    /// Returns nil when nothing has been stored yet. Throws rather than reporting an empty
    /// document, so unreadable bytes are not mistaken for "the greenhouse was never turned on".
    func load() throws -> ShortcutGreenhouseDocument? {
        guard let object = defaults.object(forKey: key) else { return nil }
        guard let data = object as? Data, data.count <= ShortcutGreenhouseLimits.maximumEncodedBytes else {
            throw CocoaError(.coderReadCorrupt)
        }
        let document = try JSONDecoder().decode(ShortcutGreenhouseDocument.self, from: data)
        guard document.isValid else { throw CocoaError(.coderReadCorrupt) }
        return document
    }

    func save(_ document: ShortcutGreenhouseDocument) throws {
        guard document.isValid else { throw CocoaError(.coderInvalidValue) }
        let data = try JSONEncoder().encode(document)
        guard data.count <= ShortcutGreenhouseLimits.maximumEncodedBytes else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        defaults.set(data, forKey: key)
    }

    func remove() {
        defaults.removeObject(forKey: key)
    }
}
