import Foundation

/// Preserves unreadable preferences until the user explicitly resets the patch bay.
nonisolated struct PatchBayRepository {
    private let defaults: UserDefaults
    private let key = "dock.patch-bay.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() throws -> PatchBayDocument {
        guard let object = defaults.object(forKey: key) else { return PatchBayDocument() }
        guard let bytes = object as? Data, bytes.count <= 64 * 1024 else {
            throw CocoaError(.coderReadCorrupt)
        }
        let document = try JSONDecoder().decode(PatchBayDocument.self, from: bytes)
        guard document.isValid else { throw CocoaError(.coderReadCorrupt) }
        return document
    }

    func save(_ document: PatchBayDocument) throws {
        guard document.isValid else { throw CocoaError(.coderInvalidValue) }
        let bytes = try JSONEncoder().encode(document)
        guard bytes.count <= 64 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
        defaults.set(bytes, forKey: key)
    }

    func reset() { defaults.removeObject(forKey: key) }
}
