import Foundation

/// Display metadata and pins use separate keys. The existing settings key remains shared defaults.
struct DisplayProfilesRepository {
    private let defaults: UserDefaults
    private let key = "dock.displays.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var dockModesRepository: DockModesRepository { DockModesRepository(defaults: defaults) }

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

    /// Typed storage wins. An absent v3 key migrates the existing application list once.
    func pins(for id: String, seed: () -> [ApplicationReference]) throws -> [DockPin] {
        let typed = DockPinsRepository(defaults: defaults, displayID: id)
        if let pins = try typed.load() { return pins }
        let applications = try savedApplications(forKey: "dock.favorites.v2.\(id)") ?? seed()
        let pins = applications.map(DockPin.application)
        try typed.save(pins)
        return pins
    }
    func existingPins(for id: String) throws -> [DockPin]? {
        let typedKey = "dock.pins.v3.\(id)"
        guard defaults.object(forKey: typedKey) != nil || defaults.object(forKey: "dock.favorites.v2.\(id)") != nil else { return nil }
        return try pins(for: id) { [] }
    }
    func savePins(_ pins: [DockPin], for id: String) throws {
        try DockPinsRepository(defaults: defaults, displayID: id).save(pins)
    }
    func legacyPins(seed: () -> [ApplicationReference]) throws -> [DockPin] {
        try (savedApplications(forKey: "dock.favorites.v1") ?? seed()).map(DockPin.application)
    }

    /// Migration reads legacy evidence without normalizing or rewriting it.
    private func savedApplications(forKey key: String) throws -> [ApplicationReference]? {
        guard let object = defaults.object(forKey: key) else { return nil }
        guard let data = object as? Data else { throw CocoaError(.coderReadCorrupt) }
        return DockOrdering.unique(try JSONDecoder().decode([ApplicationReference].self, from: data))
    }
}
