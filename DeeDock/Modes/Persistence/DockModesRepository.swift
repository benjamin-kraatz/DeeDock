import Foundation

/// Persistence boundary used by production preferences and deterministic failure tests.
protocol DockModesPersisting {
    func load() throws -> DockModesDocument?
    func save(_ document: DockModesDocument) throws
}

struct DockModesRepository: DockModesPersisting {
    private let defaults: UserDefaults
    private let key = "dock.modes.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() throws -> DockModesDocument? {
        guard let object = defaults.object(forKey: key) else { return nil }
        guard let data = object as? Data else { throw CocoaError(.coderReadCorrupt) }
        let document = try JSONDecoder().decode(DockModesDocument.self, from: data)
        guard document.isValid else { throw CocoaError(.coderReadCorrupt) }
        return document
    }

    func save(_ document: DockModesDocument) throws {
        guard document.isValid else { throw CocoaError(.coderInvalidValue) }
        defaults.set(try JSONEncoder().encode(document), forKey: key)
    }
}
