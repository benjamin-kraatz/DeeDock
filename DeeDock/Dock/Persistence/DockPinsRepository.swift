import Foundation

/// Stores typed pins while retaining application-only keys for downgrade and recovery evidence.
struct DockPinsRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, displayID: String) {
        self.defaults = defaults
        key = "dock.pins.v3.\(displayID)"
    }

    func load() throws -> [DockPin]? {
        guard let object = defaults.object(forKey: key) else { return nil }
        guard let data = object as? Data else { throw CocoaError(.coderReadCorrupt) }
        return DockPinEditing.unique(try JSONDecoder().decode([DockPin].self, from: data))
    }

    func save(_ pins: [DockPin]) throws {
        defaults.set(try JSONEncoder().encode(DockPinEditing.unique(pins)), forKey: key)
    }
}
