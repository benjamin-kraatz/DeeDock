import Foundation
import Observation

/// Owns named mode persistence and publishes only complete, successfully saved edits.
@MainActor @Observable
final class DockModesStore {
    private(set) var document: DockModesDocument
    private(set) var errorMessage: LocalizedStringResource?
    private(set) var requiresReset = false
    private(set) var initialized = false
    @ObservationIgnored private let repository: (any DockModesPersisting)?
    @ObservationIgnored private var sessionDisplays: [UUID: [String: DockModeDisplayConfiguration]] = [:]
    @ObservationIgnored private var recoveryDocument: DockModesDocument
    @ObservationIgnored var didChange: (() -> Void)?

    init(repository: (any DockModesPersisting)?) {
        let placeholder = DockMode(name: String(localized: .dockModeDefaultName))
        let document = DockModesDocument(modes: [placeholder], activeModeID: placeholder.id)
        self.document = document
        recoveryDocument = document
        self.repository = repository
    }

    var modes: [DockMode] { document.modes }
    var activeMode: DockMode { document.activeMode ?? document.modes[0] }
    var previousMode: DockMode? { document.previousMode }
    var canEdit: Bool { initialized && !requiresReset }

    func pins(for displayID: String) -> [DockPin] {
        if displayID.hasPrefix("display.") { return activeMode.displays[displayID]?.pins ?? [] }
        return sessionDisplays[activeMode.id]?[displayID]?.pins ?? []
    }

    func effectiveVisibility(for displayID: String?) -> DockAppVisibility {
        guard let displayID else { return activeMode.appVisibility }
        if displayID.hasPrefix("display.") {
            return activeMode.displays[displayID]?.appVisibility ?? activeMode.appVisibility
        }
        return sessionDisplays[activeMode.id]?[displayID]?.appVisibility ?? activeMode.appVisibility
    }

    func hasVisibilityOverride(for displayID: String) -> Bool {
        if displayID.hasPrefix("display.") { return activeMode.displays[displayID]?.appVisibility != nil }
        return sessionDisplays[activeMode.id]?[displayID]?.appVisibility != nil
    }

    /// Loads once after legacy profiles and pins are available, then adds every newly discovered display to every mode.
    func synchronize(displays: [DisplaySnapshot], persistentDisplayIDs: Set<String>, primaryDisplayID: String?,
                     legacyPins: [String: [DockPin]], legacyDefaultVisibility: DockAppVisibility,
                     legacyVisibilityOverrides: [String: DockAppVisibility]) {
        if !initialized {
            let fallback = makeInitialDocument(displayIDs: persistentDisplayIDs, primaryDisplayID: primaryDisplayID,
                                               legacyPins: legacyPins, defaultVisibility: legacyDefaultVisibility,
                                               visibilityOverrides: legacyVisibilityOverrides)
            recoveryDocument = fallback
            do {
                if let saved = try repository?.load() {
                    document = saved
                } else {
                    try repository?.save(fallback)
                    document = fallback
                }
            } catch {
                document = fallback
                requiresReset = true
                errorMessage = .dockModesLoadError
            }
            initialized = true
        }

        var proposed = document
        var changed = false
        for modeIndex in proposed.modes.indices {
            for id in persistentDisplayIDs where proposed.modes[modeIndex].displays[id] == nil {
                proposed.modes[modeIndex].displays[id] = seedConfiguration(
                    for: proposed.modes[modeIndex], primaryDisplayID: primaryDisplayID,
                    fallbackPins: legacyPins[id] ?? [])
                changed = true
            }
        }
        for display in displays where !display.isPersistent {
            for mode in proposed.modes where sessionDisplays[mode.id]?[display.id] == nil {
                var values = sessionDisplays[mode.id] ?? [:]
                values[display.id] = seedConfiguration(for: mode, primaryDisplayID: primaryDisplayID,
                                                       fallbackPins: legacyPins[display.id] ?? [])
                sessionDisplays[mode.id] = values
            }
        }
        let liveSessionIDs = Set(displays.filter { !$0.isPersistent }.map(\.id))
        for modeID in sessionDisplays.keys {
            sessionDisplays[modeID] = sessionDisplays[modeID]?.filter { liveSessionIDs.contains($0.key) }
        }
        guard changed, !requiresReset else { return }
        commit(proposed)
    }

    @discardableResult
    func setPins(_ pins: [DockPin], for displayID: String) -> Bool {
        guard canEdit else { return false }
        let pins = DockPinEditing.unique(pins)
        if !displayID.hasPrefix("display.") {
            var values = sessionDisplays[activeMode.id] ?? [:]
            let existing = values[displayID] ?? DockModeDisplayConfiguration(pins: [], appVisibility: nil)
            values[displayID] = DockModeDisplayConfiguration(pins: pins, appVisibility: existing.appVisibility)
            sessionDisplays[activeMode.id] = values
            didChange?()
            return true
        }
        var proposed = document
        guard let index = proposed.modes.firstIndex(where: { $0.id == proposed.activeModeID }) else { return false }
        let existing = proposed.modes[index].displays[displayID] ?? DockModeDisplayConfiguration(pins: [], appVisibility: nil)
        proposed.modes[index].displays[displayID] = DockModeDisplayConfiguration(pins: pins, appVisibility: existing.appVisibility)
        return commit(proposed)
    }

    func setDefaultVisibility(_ visibility: DockAppVisibility) {
        guard canEdit else { return }
        var proposed = document
        guard let index = proposed.modes.firstIndex(where: { $0.id == proposed.activeModeID }) else { return }
        proposed.modes[index].appVisibility = visibility
        _ = commit(proposed)
    }

    func setVisibility(_ visibility: DockAppVisibility, for displayID: String) {
        guard canEdit else { return }
        if !displayID.hasPrefix("display.") {
            var values = sessionDisplays[activeMode.id] ?? [:]
            let existing = values[displayID] ?? DockModeDisplayConfiguration(pins: [], appVisibility: nil)
            values[displayID] = DockModeDisplayConfiguration(pins: existing.pins, appVisibility: visibility)
            sessionDisplays[activeMode.id] = values
            didChange?()
            return
        }
        var proposed = document
        guard let index = proposed.modes.firstIndex(where: { $0.id == proposed.activeModeID }) else { return }
        let existing = proposed.modes[index].displays[displayID] ?? DockModeDisplayConfiguration(pins: [], appVisibility: nil)
        proposed.modes[index].displays[displayID] = DockModeDisplayConfiguration(pins: existing.pins, appVisibility: visibility)
        _ = commit(proposed)
    }

    func useDefaultVisibility(for displayID: String) {
        guard canEdit else { return }
        if !displayID.hasPrefix("display.") {
            guard var values = sessionDisplays[activeMode.id], var existing = values[displayID] else { return }
            existing.appVisibility = nil
            values[displayID] = existing
            sessionDisplays[activeMode.id] = values
            didChange?()
            return
        }
        var proposed = document
        guard let index = proposed.modes.firstIndex(where: { $0.id == proposed.activeModeID }),
              var existing = proposed.modes[index].displays[displayID] else { return }
        existing.appVisibility = nil
        proposed.modes[index].displays[displayID] = existing
        _ = commit(proposed)
    }

    func restoreDefaultVisibility() { setDefaultVisibility(.showAll) }

    @discardableResult
    func activate(_ id: UUID) -> Bool {
        guard canEdit, id != document.activeModeID, document.modes.contains(where: { $0.id == id }) else { return false }
        var proposed = document
        proposed.previousModeID = proposed.activeModeID
        proposed.activeModeID = id
        return commit(proposed)
    }

    @discardableResult
    func activatePrevious() -> Bool {
        guard let id = document.previousModeID else { return false }
        return activate(id)
    }

    @discardableResult
    func duplicateActive(named requestedName: String? = nil) -> UUID? {
        duplicate(activeMode.id, named: requestedName)
    }

    @discardableResult
    func duplicate(_ sourceID: UUID, named requestedName: String? = nil) -> UUID? {
        guard canEdit else { return nil }
        guard let source = document.modes.first(where: { $0.id == sourceID }) else { return nil }
        let name = requestedName.map(DockModeNaming.normalized)
            ?? DockModeNaming.copyName(for: source.name, in: document.modes)
        guard DockModeNaming.isAvailable(name, in: document.modes) else { return nil }
        let duplicate = DockMode(name: name, appVisibility: source.appVisibility, displays: source.displays)
        var proposed = document
        let sourceIndex = proposed.modes.firstIndex(where: { $0.id == source.id }) ?? proposed.modes.endIndex - 1
        proposed.modes.insert(duplicate, at: proposed.modes.index(after: sourceIndex))
        guard commit(proposed) else { return nil }
        sessionDisplays[duplicate.id] = sessionDisplays[source.id]
        return duplicate.id
    }

    @discardableResult
    func rename(_ id: UUID, to requestedName: String) -> Bool {
        let name = DockModeNaming.normalized(requestedName)
        guard canEdit, DockModeNaming.isAvailable(name, in: document.modes, excluding: id) else { return false }
        var proposed = document
        guard let index = proposed.modes.firstIndex(where: { $0.id == id }) else { return false }
        proposed.modes[index].name = name
        return commit(proposed)
    }

    @discardableResult
    func move(_ id: UUID, by distance: Int) -> Bool {
        guard canEdit, let index = document.modes.firstIndex(where: { $0.id == id }),
              document.modes.indices.contains(index + distance) else { return false }
        var proposed = document
        proposed.modes.swapAt(index, index + distance)
        return commit(proposed)
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        guard canEdit, document.modes.count > 1,
              let index = document.modes.firstIndex(where: { $0.id == id }) else { return false }
        var proposed = document
        proposed.modes.remove(at: index)
        if proposed.activeModeID == id {
            proposed.activeModeID = proposed.modes[min(index, proposed.modes.count - 1)].id
            proposed.previousModeID = nil
        } else if proposed.previousModeID == id {
            proposed.previousModeID = nil
        }
        guard commit(proposed) else { return false }
        sessionDisplays[id] = nil
        return true
    }

    /// Explicit recovery is the only operation allowed to replace unreadable mode bytes.
    func reset() {
        do {
            try repository?.save(recoveryDocument)
            document = recoveryDocument
            requiresReset = false
            errorMessage = nil
            didChange?()
        } catch { errorMessage = .dockModesSaveError }
    }

    private func makeInitialDocument(displayIDs: Set<String>, primaryDisplayID: String?,
                                     legacyPins: [String: [DockPin]], defaultVisibility: DockAppVisibility,
                                     visibilityOverrides: [String: DockAppVisibility]) -> DockModesDocument {
        let displays = displayIDs.reduce(into: [String: DockModeDisplayConfiguration]()) { result, id in
            result[id] = DockModeDisplayConfiguration(pins: DockPinEditing.unique(legacyPins[id] ?? []),
                                                      appVisibility: visibilityOverrides[id])
        }
        let mode = DockMode(name: String(localized: .dockModeDefaultName),
                            appVisibility: defaultVisibility, displays: displays)
        return DockModesDocument(modes: [mode], activeModeID: mode.id)
    }

    private func seedConfiguration(for mode: DockMode, primaryDisplayID: String?,
                                   fallbackPins: [DockPin]) -> DockModeDisplayConfiguration {
        let source = primaryDisplayID.flatMap { mode.displays[$0] }
            ?? mode.displays.sorted(by: { $0.key < $1.key }).first?.value
        return DockModeDisplayConfiguration(pins: source?.pins ?? DockPinEditing.unique(fallbackPins), appVisibility: nil)
    }

    @discardableResult
    private func commit(_ proposed: DockModesDocument) -> Bool {
        guard proposed != document, proposed.isValid else { return proposed == document }
        do {
            try repository?.save(proposed)
            document = proposed
            errorMessage = nil
            didChange?()
            return true
        } catch {
            errorMessage = .dockModesSaveError
            return false
        }
    }
}
