import Foundation
import Observation

/// Owns remembered display configuration and independent pins, including disconnected profiles.
@MainActor @Observable
final class DisplayProfilesStore {
    let defaults: DockSettingsStore
    private(set) var document = DisplayProfilesDocument()
    private(set) var displays: [DisplaySnapshot] = []
    private(set) var pinLists: [String: [DockPin]] = [:]
    private(set) var pinErrors: [String: LocalizedStringResource] = [:]
    private(set) var errorMessage: LocalizedStringResource?
    private(set) var requiresReset = false
    @ObservationIgnored private let repository: DisplayProfilesRepository?
    @ObservationIgnored var didChange: (() -> Void)?

    init(defaults: DockSettingsStore, repository: DisplayProfilesRepository?) {
        self.defaults = defaults
        self.repository = repository
        do { document = try repository?.load() ?? DisplayProfilesDocument() }
        catch { requiresReset = true; errorMessage = .displayProfilesError }
    }

    var remembered: [DisplayProfile] {
        let connected = Set(displays.map(\.id))
        return document.profiles.values.filter { $0.isPersistent && !connected.contains($0.id) }
            .sorted { $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func effectiveSettings(for id: String) -> DockSettings {
        document.profiles[id]?.overrides.resolving(defaults.value) ?? defaults.value
    }

    /// Primary-first seeding makes simultaneous discovery deterministic. Existing empty pins win.
    /// This method does not emit didChange: its caller is already reconciling the display snapshot.
    func synchronize(_ snapshots: [DisplaySnapshot], starterPins: () -> [ApplicationReference]) {
        displays = DisplayPolicy.ordered(snapshots)
        var proposed = document
        if proposed.initialPrimaryID == nil, let primary = displays.first(where: { $0.isPrimary && $0.isPersistent }) {
            proposed.initialPrimaryID = primary.id
        }
        let liveIDs = Set(displays.map(\.id))
        proposed.profiles = proposed.profiles.filter { $0.value.isPersistent || liveIDs.contains($0.key) }
        for display in displays {
            if proposed.profiles[display.id] == nil { proposed.profiles[display.id] = DisplayProfile(id: display.id, name: display.name) }
            proposed.profiles[display.id]?.name = display.name
        }
        if proposed != document {
            if !requiresReset {
                do { try repository?.save(proposed) }
                catch { errorMessage = .displayProfilesError; requiresReset = true }
            }
            document = proposed
        }
        pinLists = pinLists.filter { proposed.profiles[$0.key] != nil }
        pinErrors = pinErrors.filter { proposed.profiles[$0.key] != nil }
        for display in displays where pinLists[display.id] == nil {
            do {
                if display.isPersistent, let existing = try repository?.existingPins(for: display.id) {
                    pinLists[display.id] = existing
                    continue
                }
                let seed: [DockPin]
                let primaryID = displays.first(where: \.isPrimary)?.id
                if let primaryID, primaryID != display.id, pinErrors[primaryID] != nil {
                    throw CocoaError(.coderReadCorrupt)
                } else if let primaryID, primaryID != display.id, let primaryPins = pinLists[primaryID] {
                    seed = primaryPins
                } else if let original = document.initialPrimaryID, original != display.id,
                          let originalPins = try repository?.existingPins(for: original) {
                    seed = originalPins
                } else { seed = try repository?.legacyPins(seed: starterPins) ?? starterPins().map(DockPin.application) }
                if display.isPersistent && !requiresReset { try repository?.savePins(seed, for: display.id) }
                pinLists[display.id] = seed
            } catch {
                pinLists[display.id] = []
                pinErrors[display.id] = .errorLoadPins(details: error.localizedDescription)
            }
        }
    }

    /// Changes just one explicit override, even if its value equals today's shared default.
    func update<Value>(_ id: String, keyPath: WritableKeyPath<DockSettings, Value>, to value: Value) {
        guard let field = DockSettingField.allCases.first(where: { $0.keyPath == keyPath }) else { return }
        var effective = effectiveSettings(for: id)
        effective[keyPath: keyPath] = value
        guard let normalized = effective.normalized else { return }
        edit(id) { $0.overrides.set(field, from: normalized) }
    }

    /// Applies several explicit overrides as one saved display-profile edit.
    func update(_ id: String, fields: [DockSettingField], mutation: (inout DockSettings) -> Void) {
        var effective = effectiveSettings(for: id)
        mutation(&effective)
        guard let normalized = effective.normalized else { return }
        edit(id) { profile in fields.forEach { profile.overrides.set($0, from: normalized) } }
    }
    func useDefault(_ field: DockSettingField, for id: String) { edit(id) { $0.overrides.set(field, from: nil) } }
    func useDefaults(for id: String) { edit(id) { $0.overrides = DockSettingsOverrides() } }
    func setEnabled(_ enabled: Bool, for id: String) { edit(id) { $0.enabled = enabled } }

    private func edit(_ id: String, mutation: (inout DisplayProfile) -> Void) {
        guard !requiresReset, var profile = document.profiles[id] else { return }
        mutation(&profile)
        var proposed = document
        proposed.profiles[id] = profile
        do {
            try repository?.save(proposed)
            document = proposed
            errorMessage = nil
            didChange?()
        } catch { errorMessage = .displayProfilesError }
    }

    /// Saves only this display's pins. Failed loads remain blocked instead of destroying saved bytes.
    func savePins(_ pins: [DockPin], for id: String) throws {
        guard !requiresReset, pinErrors[id] == nil, let profile = document.profiles[id] else { throw CocoaError(.coderReadCorrupt) }
        let unique = DockPinEditing.unique(pins)
        if profile.isPersistent { try repository?.savePins(unique, for: id) }
        pinLists[id] = unique
        didChange?()
    }
}
