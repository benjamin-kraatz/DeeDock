import Foundation

/// Folds the retired Dock Modes store back into the single configuration, once.
///
/// While modes existed, the active mode owned three values: each persistent display's pins,
/// the shared app-visibility default, and each display's app-visibility override. The keys that
/// held those values before modes (`dock.pins.v3.<id>`, `dock.settings.v1`, `dock.displays.v1`)
/// stopped changing when the modes store was created. This writes the active mode's values back
/// to those keys and then removes `dock.modes.v1`, so every dock keeps what it showed before the
/// update. Inactive modes and their recipes are discarded.
///
/// Run it before `DockSettingsStore` and `DisplayProfilesStore` load. The modes key is removed only
/// after every write succeeds, so a quit or failure midway repeats the same writes next launch.
/// Without that key the migration does nothing.
struct DockModesMigration {
    static let modesKey = "dock.modes.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Applies the active mode, then deletes the modes store.
    ///
    /// Unreadable or invalid mode data leaves the other keys unchanged. Those keys were already what
    /// the docks showed, because the old store fell back to them when it could not load. An unreadable
    /// settings or profiles document is skipped as well: those stores show an error and wait for an
    /// explicit reset, and nothing else may overwrite their saved bytes.
    func run() {
        guard let object = defaults.object(forKey: Self.modesKey) else { return }
        if let data = object as? Data, let document = try? JSONDecoder().decode(SavedModes.self, from: data),
           let active = document.validActiveMode {
            do { try apply(active) } catch { return }
        }
        defaults.removeObject(forKey: Self.modesKey)
    }

    private func apply(_ mode: SavedMode) throws {
        for (id, display) in mode.displays {
            try DockPinsRepository(defaults: defaults, displayID: id).save(display.pins)
        }

        let settingsRepository = DockSettingsRepository(defaults: defaults)
        if var settings = try? settingsRepository.load(), settings.appVisibility != mode.appVisibility {
            settings.appVisibility = mode.appVisibility
            try settingsRepository.save(settings)
        }

        let profilesRepository = DisplayProfilesRepository(defaults: defaults)
        if var profiles = try? profilesRepository.load() {
            let original = profiles
            // A display without a mode entry would have been seeded with no override, so clear it.
            for id in profiles.profiles.keys where profiles.profiles[id]?.isPersistent == true {
                profiles.profiles[id]?.overrides.appVisibility = mode.displays[id]?.appVisibility
            }
            if profiles != original { try profilesRepository.save(profiles) }
        }
    }
}

/// The parts of the retired `dock.modes.v1` document the migration reads. Recipes are ignored.
private struct SavedModes: Decodable {
    var version: Int
    var modes: [SavedMode]
    var activeModeID: UUID
    var previousModeID: UUID?

    /// Mirrors the old store's validation. A document it rejected never drove a dock,
    /// so it yields no mode here either.
    var validActiveMode: SavedMode? {
        guard version == 1, let active = modes.first(where: { $0.id == activeModeID }) else { return nil }
        let ids = modes.map(\.id)
        guard Set(ids).count == ids.count else { return nil }
        let names = modes.map {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        guard names.allSatisfy({ !$0.isEmpty }), Set(names).count == names.count else { return nil }
        if let previousModeID, previousModeID == activeModeID || !ids.contains(previousModeID) { return nil }
        let displaysValid = modes.allSatisfy { mode in
            mode.displays.allSatisfy { id, display in
                id.hasPrefix("display.") && DockPinEditing.unique(display.pins) == display.pins
            }
        }
        return displaysValid ? active : nil
    }
}

private struct SavedMode: Decodable {
    struct Display: Decodable {
        var pins: [DockPin]
        var appVisibility: DockAppVisibility?
    }

    var id: UUID
    var name: String
    var appVisibility: DockAppVisibility
    var displays: [String: Display]
}
