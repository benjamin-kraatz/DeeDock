import Foundation

/// Stores only approved capsule text and stable application/window identities.
nonisolated struct SessionCapsuleRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "dock.session-capsules.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() throws -> SessionCapsuleDocument? {
        guard let object = defaults.object(forKey: key) else { return nil }
        guard let data = object as? Data else { throw CocoaError(.coderReadCorrupt) }
        let document = try JSONDecoder().decode(SessionCapsuleDocument.self, from: data)
        guard document.isValid else { throw CocoaError(.coderReadCorrupt) }
        return document
    }

    func save(_ document: SessionCapsuleDocument) throws {
        guard document.isValid else { throw CocoaError(.coderInvalidValue) }
        defaults.set(try JSONEncoder().encode(document), forKey: key)
    }
}
