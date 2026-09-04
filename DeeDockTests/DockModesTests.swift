import Foundation
import Testing

@MainActor
struct DockModesTests {
    @Test("Existing layouts migrate once without changing legacy keys")
    func legacyMigration() throws {
        let suite = "DockModesMigration.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let primary = DisplayFixtures.screen("primary", runtimeID: 1, primary: true)
        let other = DisplayFixtures.screen("other", runtimeID: 2, x: -1600)
        let first = DisplayFixtures.app("first")
        let second = DisplayFixtures.app("second")
        let profilesRepository = DisplayProfilesRepository(defaults: preferences)
        try profilesRepository.save(DisplayProfilesDocument(initialPrimaryID: primary.id, profiles: [
            primary.id: DisplayProfile(id: primary.id, name: primary.name),
            other.id: DisplayProfile(id: other.id, name: other.name,
                                     overrides: DockSettingsOverrides(appVisibility: .collapseRunning))
        ]))
        try profilesRepository.savePins([.application(first)], for: primary.id)
        try profilesRepository.savePins([.application(second)], for: other.id)
        let legacyPrimary = try #require(preferences.data(forKey: "dock.pins.v3.\(primary.id)"))

        var settings = DockSettings.defaults
        settings.appVisibility = .hidePinned
        let defaults = DockSettingsStore(repository: nil)
        defaults.update(\.appVisibility, to: settings.appVisibility)
        let profiles = DisplayProfilesStore(defaults: defaults, repository: profilesRepository)
        profiles.synchronize([other, primary]) { [] }

        #expect(profiles.modes.modes.count == 1)
        #expect(profiles.modes.activeMode.name == String(localized: .dockModeDefaultName))
        #expect(profiles.pinLists[primary.id] == [.application(first)])
        #expect(profiles.pinLists[other.id] == [.application(second)])
        #expect(profiles.effectiveSettings(for: primary.id).appVisibility == .hidePinned)
        #expect(profiles.effectiveSettings(for: other.id).appVisibility == .collapseRunning)
        #expect(preferences.data(forKey: "dock.pins.v3.\(primary.id)") == legacyPrimary)
    }

    @Test("Live edits stay in their mode and Previous toggles the last two")
    func liveEditsAndPrevious() throws {
        let profiles = DisplayProfilesStore(defaults: DockSettingsStore(repository: nil), repository: nil)
        let display = DisplayFixtures.screen("primary", runtimeID: 1, primary: true)
        let original = DisplayFixtures.app("original")
        let writing = DisplayFixtures.app("writing")
        let folder = FolderReference(url: URL(fileURLWithPath: "/tmp/Writing"), name: "Writing",
                                     bookmarkData: Data([1, 2, 3]))
        profiles.synchronize([display]) { [original] }
        let firstID = profiles.modes.activeMode.id
        let secondID = try #require(profiles.modes.duplicateActive(named: "Writing"))
        #expect(profiles.modes.activate(secondID))
        try profiles.savePins([.application(writing), .folder(folder)], for: display.id)
        profiles.updateDefaultVisibility(.collapsePinned)
        profiles.update(display.id, keyPath: \.appVisibility, to: .hideRunning)

        #expect(profiles.modes.activatePrevious())
        #expect(profiles.modes.activeMode.id == firstID)
        #expect(profiles.pinLists[display.id] == [.application(original)])
        #expect(profiles.effectiveSettings(for: display.id).appVisibility == .showAll)
        #expect(profiles.modes.activatePrevious())
        #expect(profiles.modes.activeMode.id == secondID)
        #expect(profiles.pinLists[display.id] == [.application(writing), .folder(folder)])
        #expect(profiles.effectiveSettings(for: display.id).appVisibility == .hideRunning)
        profiles.useDefault(.appVisibility, for: display.id)
        #expect(profiles.effectiveSettings(for: display.id).appVisibility == .collapsePinned)
    }

    @Test("Names, ordering, duplication, and active deletion remain deterministic")
    func management() throws {
        let profiles = DisplayProfilesStore(defaults: DockSettingsStore(repository: nil), repository: nil)
        let display = DisplayFixtures.screen("primary", runtimeID: 1, primary: true)
        profiles.synchronize([display]) { [] }
        let original = profiles.modes.activeMode.id
        let work = try #require(profiles.modes.duplicateActive(named: "Work"))
        #expect(profiles.modes.duplicateActive(named: " work ") == nil)
        #expect(profiles.modes.rename(work, to: "Writing"))
        #expect(profiles.modes.move(work, by: -1))
        #expect(profiles.modes.modes.first?.id == work)
        #expect(profiles.modes.activate(work))
        #expect(profiles.modes.delete(work))
        #expect(profiles.modes.activeMode.id == original)
        #expect(profiles.modes.previousMode == nil)
        #expect(!profiles.modes.delete(original))
    }

    @Test("A new display copies the primary layout in every mode")
    func newDisplaySeeding() throws {
        let profiles = DisplayProfilesStore(defaults: DockSettingsStore(repository: nil), repository: nil)
        let primary = DisplayFixtures.screen("primary", runtimeID: 1, primary: true)
        let added = DisplayFixtures.screen("added", runtimeID: 2, x: -1600)
        let personalPin = DisplayFixtures.app("personal")
        let workPin = DisplayFixtures.app("work")
        profiles.synchronize([primary]) { [personalPin] }
        let personalID = profiles.modes.activeMode.id
        let workID = try #require(profiles.modes.duplicateActive(named: "Work"))
        #expect(profiles.modes.activate(workID))
        try profiles.savePins([.application(workPin)], for: primary.id)
        profiles.synchronize([added, primary]) { [] }

        let personal = try #require(profiles.modes.modes.first { $0.id == personalID })
        let work = try #require(profiles.modes.modes.first { $0.id == workID })
        #expect(personal.displays[added.id]?.pins == [.application(personalPin)])
        #expect(work.displays[added.id]?.pins == [.application(workPin)])
        #expect(work.displays[added.id]?.appVisibility == nil)
    }

    @Test("A failed save cannot partially switch modes")
    func atomicFailure() throws {
        let first = DockMode(id: UUID(), name: "First")
        let second = DockMode(id: UUID(), name: "Second")
        let document = DockModesDocument(modes: [first, second], activeModeID: first.id)
        let repository = FailingDockModesRepository(document: document)
        let store = DockModesStore(repository: repository)
        store.synchronize(displays: [], persistentDisplayIDs: [], primaryDisplayID: nil,
                          legacyPins: [:], legacyDefaultVisibility: .showAll,
                          legacyVisibilityOverrides: [:])
        repository.failsSaves = true

        #expect(!store.activate(second.id))
        #expect(store.document.activeModeID == first.id)
        #expect(store.document.previousModeID == nil)
        #expect(store.errorMessage != nil)
    }

    @Test("Corrupt mode data stays locked until explicit reset")
    func corruptStorage() throws {
        let suite = "DockModesCorrupt.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(Data("corrupt".utf8), forKey: "dock.modes.v1")
        let store = DockModesStore(repository: DockModesRepository(defaults: preferences))
        store.synchronize(displays: [], persistentDisplayIDs: [], primaryDisplayID: nil,
                          legacyPins: [:], legacyDefaultVisibility: .showAll,
                          legacyVisibilityOverrides: [:])
        #expect(store.requiresReset)
        #expect(store.duplicateActive(named: "Blocked") == nil)
        #expect(preferences.data(forKey: "dock.modes.v1") == Data("corrupt".utf8))
        store.reset()
        #expect(!store.requiresReset)
        #expect(try DockModesRepository(defaults: preferences).load()?.isValid == true)
    }

    @Test("Picker geometry clamps to a negative-origin visible frame", arguments: DockEdge.allCases)
    func pickerGeometry(edge: DockEdge) {
        let visible = CGRect(x: -1900, y: -160, width: 1500, height: 900)
        let source = CGRect(x: -500, y: 680, width: 48, height: 48)
        let frame = DockModePickerGeometry.frame(
            anchor: DockModePickerAnchor(source: source, edge: edge, visibleFrame: visible), modeCount: 20)
        #expect(visible.insetBy(dx: DockModePickerGeometry.margin, dy: DockModePickerGeometry.margin).contains(frame))
    }

    @Test("Picker navigation clamps and chooses the selected stable identity")
    func pickerNavigation() throws {
        let first = DockMode(name: "First")
        let second = DockMode(name: "Second")
        let state = DockModePickerState(modes: [first, second], activeModeID: first.id)
        var chosen: UUID?
        state.choose = { chosen = $0 }
        state.select(by: 8)
        #expect(state.selectedID == second.id)
        state.chooseSelection()
        #expect(chosen == second.id)
        state.select(by: -8)
        #expect(state.selectedID == first.id)
    }
}

@MainActor
private final class FailingDockModesRepository: DockModesPersisting {
    let document: DockModesDocument
    var failsSaves = false
    init(document: DockModesDocument) { self.document = document }
    func load() throws -> DockModesDocument? { document }
    func save(_ document: DockModesDocument) throws {
        if failsSaves { throw CocoaError(.fileWriteUnknown) }
    }
}
