import Foundation

/// Display metadata and pins use separate keys. The existing settings key remains shared defaults.
struct DisplayProfilesRepository {
    private let defaults: UserDefaults
    private let key = "dock.displays.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() throws -> DisplayProfilesDocument {
        guard let object = defaults.object(forKey: key) else { return DisplayProfilesDocument() }
        guard let data = object as? Data else { throw CocoaError(.coderReadCorrupt) }
        let value = try JSONDecoder().decode(DisplayProfilesDocument.self, from: data)
        guard value.profiles.allSatisfy({ $0.key == $0.value.id && $0.value.isPersistent
            && $0.value.overrides.resolving(.defaults).isValid }) else { throw CocoaError(.coderReadCorrupt) }
        return value
    }

    func save(_ document: DisplayProfilesDocument) throws {
        var persistent = document
        persistent.profiles = persistent.profiles.filter { $0.value.isPersistent }
        defaults.set(try JSONEncoder().encode(persistent), forKey: key)
    }

    /// Loading seeds only an absent key; an empty list and malformed data are never reseeded.
    func pins(for id: String, seed: () -> [ApplicationReference]) throws -> [ApplicationReference] {
        try FavoritesRepository(defaults: defaults, key: "dock.favorites.v2.\(id)").load(seed: seed)
    }
    func existingPins(for id: String) throws -> [ApplicationReference]? {
        guard defaults.object(forKey: "dock.favorites.v2.\(id)") != nil else { return nil }
        return try pins(for: id) { [] }
    }
    func savePins(_ pins: [ApplicationReference], for id: String) throws {
        try FavoritesRepository(defaults: defaults, key: "dock.favorites.v2.\(id)").save(pins)
    }
    func legacyPins(seed: () -> [ApplicationReference]) throws -> [ApplicationReference] {
        try FavoritesRepository(defaults: defaults).load(seed: seed)
    }
}
