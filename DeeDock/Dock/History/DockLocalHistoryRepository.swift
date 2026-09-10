import Foundation

/// Stores the shared local history document. One list for the whole app, not per display.
nonisolated struct DockLocalHistoryRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "dock.local-history.v1") {
        self.defaults = defaults
        self.key = key
    }

    /// Returns nil when nothing has been stored yet. Throws rather than reporting empty
    /// history, so unreadable bytes are not mistaken for a privacy-empty document.
    func load() throws -> DockLocalHistoryDocument? {
        guard let object = defaults.object(forKey: key) else { return nil }
        guard let data = object as? Data, data.count <= DockLocalHistoryLimits.maximumEncodedBytes else {
            throw CocoaError(.coderReadCorrupt)
        }
        let document = try JSONDecoder().decode(DockLocalHistoryDocument.self, from: data)
        guard document.isValid else { throw CocoaError(.coderReadCorrupt) }
        return document
    }

    /// Refuses an invalid document so a failed load cannot be followed by a write that
    /// destroys the evidence still sitting in storage.
    func save(_ document: DockLocalHistoryDocument) throws {
        guard document.isValid else { throw CocoaError(.coderInvalidValue) }
        let data = try JSONEncoder().encode(document)
        guard data.count <= DockLocalHistoryLimits.maximumEncodedBytes else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        defaults.set(data, forKey: key)
    }

    func remove() {
        defaults.removeObject(forKey: key)
    }
}
