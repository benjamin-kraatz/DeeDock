import AppKit
import Foundation
import Testing

@MainActor
struct DockLocalHistoryTests {
    private func store(_ suite: String) throws -> (DockLocalHistoryStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (DockLocalHistoryStore(repository: DockLocalHistoryRepository(defaults: defaults)), defaults)
    }

    private func pin(_ id: String) -> DockPin {
        .application(DisplayFixtures.app(id))
    }

    @Test("Pin add, remove, and move are recorded; presentation-only writes are not")
    func pinMutations() throws {
        let safari = pin("safari")
        let mail = pin("mail")
        let calendar = pin("calendar")
        #expect(DockLocalHistoryPinDiff.mutations(previous: [], next: [safari]) == [
            .added(id: safari.id, name: "safari")
        ])
        #expect(DockLocalHistoryPinDiff.mutations(previous: [safari, mail], next: [safari]) == [
            .removed(id: mail.id, name: "mail")
        ])
        #expect(DockLocalHistoryPinDiff.mutations(previous: [safari, mail, calendar], next: [safari, calendar, mail]) == [
            .moved(id: mail.id, name: "mail")
        ])
        #expect(DockLocalHistoryPinDiff.mutations(previous: [safari, mail, calendar], next: [calendar, mail, safari]) == [
            .reordered
        ])
        #expect(DockLocalHistoryPinDiff.mutations(previous: [safari, mail], next: [safari, mail]).isEmpty)

        var folder = FolderReference(url: URL(fileURLWithPath: "/Fixtures/Downloads"), name: "Downloads",
                                     bookmarkData: Data("bookmark".utf8), presentation: .grid)
        let before = DockPin.folder(folder)
        folder.presentation = .list
        #expect(DockLocalHistoryPinDiff.mutations(previous: [before], next: [.folder(folder)]).isEmpty)
    }

    @Test("Only DDock-local pin and session kinds are written")
    func localKindsOnly() throws {
        let suite = "HistoryKinds.\(UUID().uuidString)"
        let (history, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        history.start()
        history.recordPinChange(previous: [], next: [pin("safari")], displayID: "display.primary")
        var session = FocusSession(id: UUID(), modeID: UUID(), modeName: "Deep Work", duration: 1500,
                                   remainingWhenPaused: 1500, deadline: Date().addingTimeInterval(1500), phase: .running)
        history.noteSession(session)
        session.phase = .paused
        session.deadline = nil
        session.remainingWhenPaused = 900
        history.noteSession(session)

        #expect(history.events.allSatisfy { $0.isPinEvent || $0.isSessionEvent })
        #expect(history.events.allSatisfy(\.kind.isRecognized))
        #expect(history.events.contains { $0.kind == .pinAdded && $0.subjectName == "safari" })
        #expect(history.events.contains { $0.kind == .sessionStarted && $0.subjectName == "Deep Work" })
        #expect(history.events.contains { $0.kind == .sessionPaused })
    }

    @Test("An already-running session after launch does not invent a start event")
    func noBackfillOnLaunch() throws {
        let suite = "HistoryBackfill.\(UUID().uuidString)"
        let (history, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = FocusSession(id: UUID(), modeID: UUID(), modeName: "Focus", duration: 1500,
                                   remainingWhenPaused: 1500, deadline: Date().addingTimeInterval(1500), phase: .running)
        history.start(session: session)
        history.noteSession(session)
        #expect(history.events.isEmpty)
    }

    @Test("Session events share a sessionID and close the start span on finish")
    func sessionGrouping() throws {
        let suite = "HistorySession.\(UUID().uuidString)"
        let (history, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        history.start()
        let started = Date(timeIntervalSince1970: 1_000)
        var session = FocusSession(id: UUID(), modeID: UUID(), modeName: "Writing", duration: 1500,
                                   remainingWhenPaused: 1500, deadline: started.addingTimeInterval(1500), phase: .running)
        history.noteSession(session, at: started)
        history.recordPinChange(previous: [], next: [pin("safari")], displayID: "display.primary",
                                at: started.addingTimeInterval(10))
        session.phase = .completed
        session.deadline = nil
        session.remainingWhenPaused = 0
        let finished = started.addingTimeInterval(60)
        history.noteSession(session, at: finished)

        let grouped = history.events(forSession: session.id)
        #expect(grouped.map(\.kind) == [.sessionStarted, .pinAdded, .sessionFinished])
        #expect(grouped.allSatisfy { $0.sessionID == session.id })
        #expect(grouped.first { $0.kind == .sessionStarted }?.endedAt == finished)
    }

    @Test("Recording can be paused and history can be cleared")
    func privacyControls() throws {
        let suite = "HistoryPrivacy.\(UUID().uuidString)"
        let (history, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        history.start()
        history.setRecordingEnabled(false)
        history.recordPinChange(previous: [], next: [pin("safari")], displayID: "display.primary")
        #expect(history.isEmpty)

        history.setRecordingEnabled(true)
        history.recordPinChange(previous: [], next: [pin("safari")], displayID: "display.primary")
        #expect(history.events.count == 1)
        history.clear()
        #expect(history.isEmpty)
        #expect(history.recordingEnabled)
    }

    @Test("Corrupt bytes are reported and never overwritten")
    func corruptData() throws {
        let suite = "HistoryCorrupt.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bytes = Data("not history".utf8)
        defaults.set(bytes, forKey: "dock.local-history.v1")
        #expect(throws: (any Error).self) { try DockLocalHistoryRepository(defaults: defaults).load() }

        let history = DockLocalHistoryStore(repository: DockLocalHistoryRepository(defaults: defaults))
        history.start()
        #expect(history.requiresReset)
        history.recordPinChange(previous: [], next: [pin("safari")], displayID: "display.primary")
        #expect(defaults.data(forKey: "dock.local-history.v1") == bytes)
        history.reset()
        #expect(!history.requiresReset)
        #expect(defaults.data(forKey: "dock.local-history.v1") == nil)
    }

    @Test("Unknown future kinds decode so DEE-45 can extend the same document")
    func unknownKindForwardCompatibility() throws {
        let seed = DockLocalHistoryEvent(id: UUID(), occurredAt: Date(timeIntervalSince1970: 1),
                                         kind: .pinAdded, subjectName: "clip")
        let encoded = try JSONEncoder().encode(DockLocalHistoryDocument(events: [seed]))
        let payload = try #require(String(data: encoded, encoding: .utf8)?
            .replacingOccurrences(of: "pinAdded", with: "sessionPlaybackMarker"))
        let document = try JSONDecoder().decode(DockLocalHistoryDocument.self, from: Data(payload.utf8))
        #expect(document.isValid)
        #expect(document.events.count == 1)
        #expect(document.events[0].kind == .unrecognized("sessionPlaybackMarker"))
        #expect(!document.events[0].kind.isRecognized)
        #expect(document.events[0].glanceTitle == .timelineEventUnrecognized)
    }

    @Test("An unknown document version is rejected rather than read as empty history")
    func versionGuard() throws {
        let suite = "HistoryVersion.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bytes = Data(#"{"version":99,"recordingEnabled":true,"events":[]}"#.utf8)
        defaults.set(bytes, forKey: "dock.local-history.v1")
        #expect(throws: (any Error).self) { try DockLocalHistoryRepository(defaults: defaults).load() }
        #expect(defaults.data(forKey: "dock.local-history.v1") == bytes)
    }

    @Test("Dock-axis progress maps oldest to newest and keeps same-time events selectable")
    func scrubMapping() {
        let first = DockLocalHistoryEvent(id: UUID(), occurredAt: Date(timeIntervalSince1970: 10),
                                          kind: .pinAdded, subjectName: "first")
        let second = DockLocalHistoryEvent(id: UUID(), occurredAt: Date(timeIntervalSince1970: 20),
                                           kind: .pinRemoved, subjectName: "second")
        let events = [first, second]
        #expect(DockTimelineMapping.progress(along: 0, length: 100) == 0)
        #expect(DockTimelineMapping.progress(along: 100, length: 100) == 1)
        #expect(DockTimelineMapping.event(at: 0, in: events)?.id == first.id)
        #expect(DockTimelineMapping.event(at: 1, in: events)?.id == second.id)
        #expect(DockTimelineMapping.progress(for: first, in: events) == 0)
        #expect(DockTimelineMapping.progress(for: second, in: events) == 1)

        let twinA = DockLocalHistoryEvent(id: UUID(), occurredAt: Date(timeIntervalSince1970: 50), kind: .pinAdded)
        let twinB = DockLocalHistoryEvent(id: UUID(), occurredAt: Date(timeIntervalSince1970: 50), kind: .pinRemoved)
        let twins = [twinA, twinB]
        #expect(DockTimelineMapping.event(at: 0, in: twins)?.id == twinA.id)
        #expect(DockTimelineMapping.event(at: 1, in: twins)?.id == twinB.id)
        #expect(DockTimelineMapping.event(at: 0.5, in: []) == nil)
    }

    @Test("Timeline playhead starts at the newest event and nudges along the axis")
    func timelinePlayhead() throws {
        let suite = "HistoryPlayhead.\(UUID().uuidString)"
        let (history, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        history.start()
        let start = Date(timeIntervalSince1970: 100)
        history.recordPinChange(previous: [], next: [pin("one")], displayID: "display.primary", at: start)
        history.recordPinChange(previous: [pin("one")], next: [pin("one"), pin("two")],
                                displayID: "display.primary", at: start.addingTimeInterval(30))
        let timeline = DockTimelineController(history: history)
        #expect(!timeline.presentation.isActive)
        #expect(timeline.presentation.isEmpty == false)
        timeline.begin(on: "display.primary")
        #expect(timeline.isActive(on: "display.primary"))
        #expect(timeline.progress == 1)
        #expect(timeline.selectedEvent?.subjectName == "two")
        timeline.nudge(by: -1)
        #expect(timeline.selectedEvent?.subjectName == "one")
        timeline.end()
        #expect(!timeline.isActive)
    }

    @Test("Empty history presents a privacy-ready empty scrub state")
    func emptyPresentation() throws {
        let suite = "HistoryEmpty.\(UUID().uuidString)"
        let (history, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        history.start()
        let timeline = DockTimelineController(history: history)
        timeline.begin(on: "display.primary")
        #expect(timeline.presentation.isEmpty)
        #expect(timeline.presentation.selectedEvent == nil)
        #expect(timeline.presentation.markers.isEmpty)
        #expect(timeline.presentation.recordingEnabled)
        #expect(!timeline.presentation.replayEnabled)
    }

    @Test("DockStore pin edits record through the shared history store")
    func dockStoreRecordsPins() throws {
        let suite = "HistoryDockStore.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let display = DisplayFixtures.screen("primary", runtimeID: 1, primary: true)
        let settings = DockSettingsStore(repository: nil)
        let profiles = DisplayProfilesStore(
            defaults: settings,
            repository: DisplayProfilesRepository(defaults: defaults),
            modesRepository: DockModesRepository(defaults: defaults)
        )
        profiles.synchronize([display]) { [] }
        let history = DockLocalHistoryStore(repository: DockLocalHistoryRepository(defaults: defaults))
        history.start()
        let catalog = ApplicationCatalog(service: HistoryFixtureService())
        let dock = DockStore(displayID: display.id, catalog: catalog, profiles: profiles, history: history)
        #expect(dock.savePins([.application(DisplayFixtures.app("safari"))]))
        #expect(history.events.map(\.kind) == [.pinAdded])
        #expect(dock.savePins([]))
        #expect(history.events.map(\.kind) == [.pinAdded, .pinRemoved])
    }

    @Test("Pin events store post-change order and archive the pins")
    func pinSnapshots() throws {
        let suite = "HistorySnapshots.\(UUID().uuidString)"
        let (history, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        history.start()
        #expect(!history.replayEnabled)
        let safari = pin("safari")
        let mail = pin("mail")
        history.recordPinChange(previous: [], next: [safari], displayID: "display.primary")
        history.recordPinChange(previous: [safari], next: [safari, mail], displayID: "display.primary")
        history.recordPinChange(previous: [safari, mail], next: [mail, safari], displayID: "display.primary")

        #expect(history.events.map(\.pinIDs) == [
            [safari.id],
            [safari.id, mail.id],
            [mail.id, safari.id]
        ])
        #expect(history.pinArchive[safari.id] == safari)
        #expect(history.pinArchive[mail.id] == mail)
    }

    @Test("Older documents decode with pin replay off and an empty archive")
    func replayDefaultsOnDecode() throws {
        let bytes = Data(#"{"version":1,"recordingEnabled":true,"events":[]}"#.utf8)
        let document = try JSONDecoder().decode(DockLocalHistoryDocument.self, from: bytes)
        #expect(document.isValid)
        #expect(!document.replayEnabled)
        #expect(document.pinArchive.isEmpty)
        #expect(document.recordingEnabled)
    }

    @Test("Replay reconstructs add, remove, move, and reorder from snapshots")
    func reconstructFromSnapshots() {
        let safari = pin("safari")
        let mail = pin("mail")
        let calendar = pin("calendar")
        let added = DockLocalHistoryEvent(
            id: UUID(), occurredAt: Date(timeIntervalSince1970: 1), kind: .pinAdded,
            displayID: "display.primary", subjectID: safari.id, pinIDs: [safari.id]
        )
        let addedMail = DockLocalHistoryEvent(
            id: UUID(), occurredAt: Date(timeIntervalSince1970: 2), kind: .pinAdded,
            displayID: "display.primary", subjectID: mail.id, pinIDs: [safari.id, mail.id]
        )
        let removed = DockLocalHistoryEvent(
            id: UUID(), occurredAt: Date(timeIntervalSince1970: 3), kind: .pinRemoved,
            displayID: "display.primary", subjectID: safari.id, pinIDs: [mail.id]
        )
        let moved = DockLocalHistoryEvent(
            id: UUID(), occurredAt: Date(timeIntervalSince1970: 4), kind: .pinMoved,
            displayID: "display.primary", subjectID: calendar.id, pinIDs: [calendar.id, mail.id]
        )
        let reordered = DockLocalHistoryEvent(
            id: UUID(), occurredAt: Date(timeIntervalSince1970: 5), kind: .pinsReordered,
            displayID: "display.primary", pinIDs: [mail.id, calendar.id]
        )
        let events = [added, addedMail, removed, moved, reordered]
        let current = [mail.id, calendar.id]
        #expect(DockTimelinePinReplay.pinIDs(at: 0, events: events, currentIDs: current,
                                            displayID: "display.primary") == [safari.id])
        #expect(DockTimelinePinReplay.pinIDs(at: 1, events: events, currentIDs: current,
                                            displayID: "display.primary") == [safari.id, mail.id])
        #expect(DockTimelinePinReplay.pinIDs(at: 2, events: events, currentIDs: current,
                                            displayID: "display.primary") == [mail.id])
        #expect(DockTimelinePinReplay.pinIDs(at: 3, events: events, currentIDs: current,
                                            displayID: "display.primary") == [calendar.id, mail.id])
        #expect(DockTimelinePinReplay.pinIDs(at: 4, events: events, currentIDs: current,
                                            displayID: "display.primary") == [mail.id, calendar.id])
    }

    @Test("Events without snapshots invert later add and remove from the live list")
    func reconstructWithoutSnapshots() {
        let safari = pin("safari")
        let mail = pin("mail")
        let addedSafari = DockLocalHistoryEvent(
            id: UUID(), occurredAt: Date(timeIntervalSince1970: 1), kind: .pinAdded,
            displayID: "display.primary", subjectID: safari.id
        )
        let addedMail = DockLocalHistoryEvent(
            id: UUID(), occurredAt: Date(timeIntervalSince1970: 2), kind: .pinAdded,
            displayID: "display.primary", subjectID: mail.id
        )
        let removedSafari = DockLocalHistoryEvent(
            id: UUID(), occurredAt: Date(timeIntervalSince1970: 3), kind: .pinRemoved,
            displayID: "display.primary", subjectID: safari.id
        )
        let events = [addedSafari, addedMail, removedSafari]
        let current = [mail.id]
        #expect(DockTimelinePinReplay.pinIDs(at: 2, events: events, currentIDs: current,
                                            displayID: "display.primary") == [mail.id])
        #expect(DockTimelinePinReplay.pinIDs(at: 1, events: events, currentIDs: current,
                                            displayID: "display.primary") == [mail.id, safari.id])
        #expect(DockTimelinePinReplay.pinIDs(at: 0, events: events, currentIDs: current,
                                            displayID: "display.primary") == [safari.id])
    }

    @Test("A selected event's snapshot is used even when it was recorded on another display")
    func reconstructUsesEventSnapshotAcrossDisplays() {
        let safari = pin("safari")
        let mail = pin("mail")
        let onPrimary = DockLocalHistoryEvent(
            id: UUID(), occurredAt: Date(timeIntervalSince1970: 1), kind: .pinAdded,
            displayID: "display.primary", subjectID: safari.id, pinIDs: [safari.id]
        )
        let onOther = DockLocalHistoryEvent(
            id: UUID(), occurredAt: Date(timeIntervalSince1970: 2), kind: .pinAdded,
            displayID: "display.other", subjectID: mail.id, pinIDs: [mail.id]
        )
        let events = [onPrimary, onOther]
        #expect(DockTimelinePinReplay.pinIDs(at: 1, events: events, currentIDs: [safari.id],
                                            displayID: "display.primary") == [mail.id])
        #expect(DockTimelinePinReplay.pinIDs(at: 1, events: events, currentIDs: [mail.id],
                                            displayID: "display.other") == [mail.id])
    }

    @Test("Move-only history without snapshots keeps the live pin order")
    func reconstructUnknownMovesKeepCurrent() {
        let moved = DockLocalHistoryEvent(
            id: UUID(), occurredAt: Date(timeIntervalSince1970: 1), kind: .pinMoved,
            displayID: "display.primary", subjectID: pin("safari").id
        )
        let current = [pin("safari").id, pin("mail").id]
        #expect(DockTimelinePinReplay.pinIDs(at: 0, events: [moved], currentIDs: current,
                                            displayID: "display.primary") == current)
    }

    @Test("Timeline preview does not persist pins or record new history")
    func previewDoesNotPersist() throws {
        let suite = "HistoryPreview.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let display = DisplayFixtures.screen("primary", runtimeID: 1, primary: true)
        let settings = DockSettingsStore(repository: nil)
        let profiles = DisplayProfilesStore(
            defaults: settings,
            repository: DisplayProfilesRepository(defaults: defaults),
            modesRepository: DockModesRepository(defaults: defaults)
        )
        profiles.synchronize([display]) { [] }
        let history = DockLocalHistoryStore(repository: DockLocalHistoryRepository(defaults: defaults))
        history.start()
        let catalog = ApplicationCatalog(service: HistoryFixtureService())
        let dock = DockStore(displayID: display.id, catalog: catalog, profiles: profiles, history: history)
        let safari = pin("safari")
        let mail = pin("mail")
        #expect(dock.savePins([safari]))
        #expect(history.events.count == 1)

        dock.applyTimelinePreview([mail])
        #expect(dock.pins.map(\.id) == [mail.id])
        #expect(dock.persistedPins.map(\.id) == [safari.id])
        #expect(dock.isPreviewingTimeline)
        #expect(!dock.canEditPins)
        #expect(!dock.savePins([mail, safari]))
        #expect(history.events.map(\.kind) == [.pinAdded])
        #expect(dock.persistedPins.map(\.id) == [safari.id])

        dock.clearTimelinePreview()
        #expect(dock.pins.map(\.id) == [safari.id])
        #expect(!dock.isPreviewingTimeline)
    }

    @Test("Pin replay waits for dwell, cancels on scrub, and stays off by default")
    func replayDwellAndGate() async throws {
        let suite = "HistoryReplayDwell.\(UUID().uuidString)"
        let (history, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        history.start()
        let start = Date(timeIntervalSince1970: 100)
        history.recordPinChange(previous: [], next: [pin("one")], displayID: "display.primary", at: start)
        history.recordPinChange(previous: [pin("one")], next: [pin("one"), pin("two")],
                                displayID: "display.primary", at: start.addingTimeInterval(30))
        let current = [pin("one"), pin("two")]
        var applied: [[String]] = []
        var cleared = 0

        let timeline = DockTimelineController(history: history)
        timeline.previewDwell = .milliseconds(25)
        timeline.applyPreview = { _, pins in applied.append(pins.map(\.id)) }
        timeline.clearPreview = { _ in cleared += 1 }

        timeline.begin(on: "display.primary", currentPins: current, archive: history.pinArchive)
        timeline.nudge(by: -1)
        #expect(applied.isEmpty)
        #expect(!timeline.replayPending)
        try await Task.sleep(for: .milliseconds(80))
        #expect(applied.isEmpty)
        #expect(!timeline.isReplayingPins)

        history.setReplayEnabled(true)
        timeline.begin(on: "display.primary", currentPins: current, archive: history.pinArchive)
        timeline.update(progress: 0)
        #expect(applied.isEmpty)
        #expect(timeline.replayPending)
        try await Task.sleep(for: .milliseconds(80))
        #expect(applied == [[pin("one").id]])
        #expect(timeline.isReplayingPins)

        applied = []
        timeline.nudge(by: 1)
        #expect(applied == [[pin("one").id, pin("two").id]])

        applied = []
        timeline.update(progress: 0)
        timeline.update(progress: 1)
        try await Task.sleep(for: .milliseconds(80))
        #expect(applied.isEmpty)

        timeline.end()
        #expect(cleared == 1)
    }
}

@MainActor
private final class HistoryFixtureService: ApplicationServicing {
    func runningApplications() -> [ApplicationReference] { [] }
    func defaultFavorites() -> [ApplicationReference] { [] }
    func resolvedURL(for reference: ApplicationReference) -> URL? { reference.url }
    func icon(for url: URL?) -> NSImage { NSImage(size: CGSize(width: 48, height: 48)) }
    func pruneIcons(keeping urls: Set<URL>) {}
    func openDocuments(_ urls: [URL], with reference: ApplicationReference) async throws {}
    func performPrimaryAction(_ reference: ApplicationReference) async throws -> ApplicationPrimaryActionOutcome { .opened }
    func open(_ reference: ApplicationReference) async throws {}
}
