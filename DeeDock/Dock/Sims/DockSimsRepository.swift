import Foundation

/// Stores the shared Sims document. One list for the whole app, not per display.
///
/// UserDefaults only. This type never opens a network session or a file outside the suite.
nonisolated struct DockSimsRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = DockSimsLimits.storageKey) {
        self.defaults = defaults
        self.key = key
    }

    /// Returns nil when nothing has been stored yet. Throws rather than reporting an empty
    /// document, so unreadable bytes are not mistaken for "Sims was never turned on".
    func load() throws -> DockSimsDocument? {
        guard let object = defaults.object(forKey: key) else { return nil }
        guard let data = object as? Data, data.count <= DockSimsLimits.maximumEncodedBytes else {
            throw CocoaError(.coderReadCorrupt)
        }
        let document = try JSONDecoder().decode(DockSimsDocument.self, from: data)
        guard document.isValid else { throw CocoaError(.coderReadCorrupt) }
        return document
    }

    /// Refuses an invalid document so a failed load cannot be followed by a write that
    /// destroys the evidence still sitting in storage.
    func save(_ document: DockSimsDocument) throws {
        guard document.isValid else { throw CocoaError(.coderInvalidValue) }
        let data = try JSONEncoder().encode(document)
        guard data.count <= DockSimsLimits.maximumEncodedBytes else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        defaults.set(data, forKey: key)
    }

    func remove() {
        defaults.removeObject(forKey: key)
    }
}
