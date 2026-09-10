import Foundation

/// Persists the shared stack-gravity document. One record for the whole app.
nonisolated struct StackGravityRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "dock.stack-gravity.v1") {
        self.defaults = defaults
        self.key = key
    }

    /// Returns nil when nothing has been stored yet. Throws on unreadable bytes.
    func load() throws -> StackGravityDocument? {
        guard let object = defaults.object(forKey: key) else { return nil }
        guard let data = object as? Data else { throw CocoaError(.coderReadCorrupt) }
        let document = try JSONDecoder().decode(StackGravityDocument.self, from: data)
        guard let normalized = document.normalized else { throw CocoaError(.coderReadCorrupt) }
        return normalized
    }

    func save(_ document: StackGravityDocument) throws {
        guard let normalized = document.normalized else { throw CocoaError(.coderInvalidValue) }
        defaults.set(try JSONEncoder().encode(normalized), forKey: key)
    }

    func remove() {
        defaults.removeObject(forKey: key)
    }
}
