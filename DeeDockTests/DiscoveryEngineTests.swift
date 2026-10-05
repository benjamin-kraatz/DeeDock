import Foundation
import Testing
@testable import DeeDock

/// A snoozed or uncalm tip has to leave the 69-second slot alone and let a later due tip through.
@Suite("Discovery scheduling")
@MainActor
struct DiscoveryEngineTests {
    @Test("A snoozed head yields to the next due tip and returns when the snooze ends")
    func snoozedHeadYieldsToTheNextTip() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let early = proposal(id: "early", threshold: 1, snoozeInterval: 200)
        let middle = proposal(id: "middle", threshold: 2)
        let tail = proposal(id: "tail", threshold: 3)
        let engine = DiscoveryEngine(defaults: defaults, catalog: [early, middle, tail])
        let start = Date(timeIntervalSinceReferenceDate: 20_000)

        engine.record(.clipboardChanged, at: start)
        #expect(engine.advance(at: start, canPresent: true)?.id == "early")
        engine.finish(forever: false, at: start)

        engine.record(.clipboardChanged, at: start)
        engine.record(.clipboardChanged, at: start.addingTimeInterval(1))
        engine.record(.clipboardChanged, at: start.addingTimeInterval(2))
        #expect(engine.queue == ["early", "middle", "tail"])

        let due = start.addingTimeInterval(DiscoveryEngine.spacing)
        #expect(engine.advance(at: due, canPresent: true)?.id == "middle")
        #expect(engine.queue == ["early", "tail"])

        // The queue and the session cap stay in memory. The snooze is what relaunch restores.
        let resumed = DiscoveryEngine(defaults: defaults, catalog: [early, middle, tail])
        let ready = start.addingTimeInterval(200)
        resumed.record(.clipboardChanged, at: ready)
        #expect(resumed.advance(at: ready, canPresent: true)?.id == "early")
    }

    @Test("A refused advance leaves the spacing slot available")
    func refusedAdvanceDoesNotConsumeTheSlot() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let early = proposal(id: "early", threshold: 1, snoozeInterval: 10_000)
        let later = proposal(id: "later", threshold: 2)
        let engine = DiscoveryEngine(defaults: defaults, catalog: [early, later])
        let start = Date(timeIntervalSinceReferenceDate: 30_000)

        engine.record(.clipboardChanged, at: start)
        #expect(engine.advance(at: start, canPresent: true)?.id == "early")
        engine.finish(forever: false, at: start)
        engine.record(.clipboardChanged, at: start)
        #expect(engine.queue == ["early"])

        let due = start.addingTimeInterval(DiscoveryEngine.spacing)
        #expect(engine.advance(at: due, canPresent: true) == nil)
        #expect(engine.queue == ["early"])

        let stillThisSlot = due.addingTimeInterval(1)
        engine.record(.clipboardChanged, at: stillThisSlot)
        #expect(engine.advance(at: stillThisSlot, canPresent: true)?.id == "later")
    }

    @Test("A presentation holds the next tip for the spacing interval")
    func spacingAfterPresentation() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = proposal(id: "first", threshold: 1)
        let second = proposal(id: "second", threshold: 1)
        let engine = DiscoveryEngine(defaults: defaults, catalog: [first, second])
        let start = Date(timeIntervalSinceReferenceDate: 40_000)

        engine.record(.clipboardChanged, at: start)
        #expect(engine.queue == ["first", "second"])
        #expect(engine.advance(at: start, canPresent: true)?.id == "first")
        engine.finish(forever: true, at: start)

        let early = start.addingTimeInterval(DiscoveryEngine.spacing - 1)
        #expect(engine.advance(at: early, canPresent: true) == nil)
        #expect(engine.queue == ["second"])

        let due = start.addingTimeInterval(DiscoveryEngine.spacing)
        #expect(engine.advance(at: due, canPresent: true)?.id == "second")
    }

    @Test("A tip inside its calm interval stays queued and leaves the slot in place")
    func calmIntervalDoesNotConsumeTheSlot() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let shown = proposal(id: "shown", threshold: 1, calmInterval: 0)
        let waiting = proposal(id: "waiting", threshold: 1, calmInterval: 5)
        let engine = DiscoveryEngine(defaults: defaults, catalog: [shown, waiting])
        let start = Date(timeIntervalSinceReferenceDate: 50_000)

        engine.record(.clipboardChanged, at: start)
        #expect(engine.advance(at: start, canPresent: true)?.id == "shown")
        engine.finish(forever: true, at: start)
        #expect(engine.queue == ["waiting"])

        let due = start.addingTimeInterval(DiscoveryEngine.spacing)
        engine.record(.clipboardChanged, at: due)
        #expect(engine.advance(at: due, canPresent: true) == nil)
        #expect(engine.queue == ["waiting"])
        #expect(engine.advance(at: due.addingTimeInterval(5), canPresent: true)?.id == "waiting")
    }

    private func proposal(
        id: String,
        threshold: Int,
        calmInterval: TimeInterval = 0,
        snoozeInterval: TimeInterval = 10_000
    ) -> DiscoveryProposal {
        DiscoveryProposal(
            id: id,
            signal: .clipboardChanged,
            threshold: threshold,
            calmInterval: calmInterval,
            title: .discoveryMuseumTitle,
            message: .discoveryMuseumMessage,
            action: .discoveryMuseumOpen,
            destination: .clipboardMuseum,
            snoozeInterval: snoozeInterval
        )
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "discovery.engine.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
