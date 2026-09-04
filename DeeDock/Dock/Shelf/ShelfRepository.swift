import Foundation

/// Stores the shared Shelf. One document for the whole app, not per display and not per mode.
nonisolated struct ShelfRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "dock.shelf.v1") {
        self.defaults = defaults
        self.key = key
    }

    /// Returns nil when nothing has been stored yet. Throws rather than reporting an empty Shelf,
    /// so unreadable bytes are surfaced instead of looking like the user lost their items.
    func load() throws -> ShelfDocument? {
        guard let object = defaults.object(forKey: key) else { return nil }
        guard let data = object as? Data else { throw CocoaError(.coderReadCorrupt) }
        let document = try JSONDecoder().decode(ShelfDocument.self, from: data)
        guard document.isValid else { throw CocoaError(.coderReadCorrupt) }
        return document
    }

    /// Refuses an invalid document so a failed load can never be followed by a write that
    /// destroys the evidence, or the items, still sitting in storage.
    func save(_ document: ShelfDocument) throws {
        guard document.isValid else { throw CocoaError(.coderInvalidValue) }
        defaults.set(try JSONEncoder().encode(document), forKey: key)
    }
}
