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
