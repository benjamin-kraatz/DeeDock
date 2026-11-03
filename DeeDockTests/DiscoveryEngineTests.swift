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

        engine.record(.launched, at: start)
        #expect(engine.advance(at: start, canPresent: true)?.id == "early")
        engine.finish(forever: false, at: start)

        engine.record(.launched, at: start)
        engine.record(.launched, at: start.addingTimeInterval(1))
        engine.record(.launched, at: start.addingTimeInterval(2))
        #expect(engine.queue == ["early", "middle", "tail"])

        let due = start.addingTimeInterval(DiscoveryEngine.spacing)
        #expect(engine.advance(at: due, canPresent: true)?.id == "middle")
        #expect(engine.queue == ["early", "tail"])

        // The queue and the session cap stay in memory. The snooze is what relaunch restores.
        let resumed = DiscoveryEngine(defaults: defaults, catalog: [early, middle, tail])
        let ready = start.addingTimeInterval(200)
        resumed.record(.launched, at: ready)
        #expect(resumed.advance(at: ready, canPresent: true)?.id == "early")
    }

    @Test("A refused advance leaves the spacing slot available")
    func refusedAdvanceDoesNotConsumeTheSlot() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let early = proposal(id: "early", threshold: 1, snoozeInterval: 10_000)
        // Each tip counts its own signals, so `later` reaches three on the third change.
        let later = proposal(id: "later", threshold: 3)
        let engine = DiscoveryEngine(defaults: defaults, catalog: [early, later])
        let start = Date(timeIntervalSinceReferenceDate: 30_000)

        engine.record(.launched, at: start)
        #expect(engine.advance(at: start, canPresent: true)?.id == "early")
        engine.finish(forever: false, at: start)
        engine.record(.launched, at: start)
        #expect(engine.queue == ["early"])

        let due = start.addingTimeInterval(DiscoveryEngine.spacing)
        #expect(engine.advance(at: due, canPresent: true) == nil)
        #expect(engine.queue == ["early"])

        let stillThisSlot = due.addingTimeInterval(1)
        engine.record(.launched, at: stillThisSlot)
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

        engine.record(.launched, at: start)
        #expect(engine.queue == ["first", "second"])
        #expect(engine.advance(at: start, canPresent: true)?.id == "first")
        engine.finish(forever: true, at: start)

        let early = start.addingTimeInterval(DiscoveryEngine.spacing - 1)
        #expect(engine.advance(at: early, canPresent: true) == nil)
        #expect(engine.queue == ["second"])

        // finish spent only the first tip's signal. The second shows without another one.
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

        engine.record(.launched, at: start)
        #expect(engine.advance(at: start, canPresent: true)?.id == "shown")
        engine.finish(forever: true, at: start)
        #expect(engine.queue == ["waiting"])

        let due = start.addingTimeInterval(DiscoveryEngine.spacing)
        engine.record(.launched, at: due)
        #expect(engine.advance(at: due, canPresent: true) == nil)
        #expect(engine.queue == ["waiting"])
        #expect(engine.advance(at: due.addingTimeInterval(5), canPresent: true)?.id == "waiting")
    }

    @Test("A launch announcement waits for calm, snoozes until a later launch, and stops once used")
    func launchAnnouncement() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let feed = try #require(DiscoveryProposal.catalog.first { $0.destination == .notificationFeed })
        #expect(feed.signal == .launched)
        let start = Date(timeIntervalSinceReferenceDate: 60_000)

        let engine = DiscoveryEngine(defaults: defaults, catalog: [feed])
        engine.record(.launched, at: start)
        #expect(engine.advance(at: start, canPresent: true) == nil)
        let calm = start.addingTimeInterval(feed.calmInterval)
        #expect(engine.advance(at: calm, canPresent: true)?.id == feed.id)
        engine.finish(forever: false, at: calm)
        // The launch signal is spent. Nothing returns in this session.
        #expect(engine.advance(at: calm.addingTimeInterval(feed.snoozeInterval), canPresent: true) == nil)

        // A relaunch inside the snooze queues it but does not show it.
        let relaunch = calm.addingTimeInterval(3600)
        let second = DiscoveryEngine(defaults: defaults, catalog: [feed])
        second.record(.launched, at: relaunch)
        #expect(second.advance(at: relaunch.addingTimeInterval(feed.calmInterval), canPresent: true) == nil)

        // After the snooze, a launch shows it again, unless the feed was turned on.
        let later = calm.addingTimeInterval(feed.snoozeInterval + 1)
        let third = DiscoveryEngine(defaults: defaults, catalog: [feed])
        third.record(.launched, at: later)
        third.markUsed(.notificationFeed)
        #expect(third.queue.isEmpty)
        #expect(third.advance(at: later.addingTimeInterval(feed.calmInterval), canPresent: true) == nil)
    }

    /// How a shown tip ended. The callout's timeout and **Tomorrow** both snooze it; neither may
    /// spend the launch signal of the tips queued behind it.
    enum LaunchTipEnding: CaseIterable {
        case timedOut, snoozed, dismissed
        var visibleFor: TimeInterval { self == .timedOut ? 20 : 3 }
        var forever: Bool { self == .dismissed }
    }

    @Test("Radar's launch tip still shows after Robi's tip ends in the same session",
          arguments: LaunchTipEnding.allCases)
    func launchTipsSurviveAnEarlierOne(ending: LaunchTipEnding) throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = DiscoveryProposal.catalog.filter { $0.signal == .launched }
        let robi = try #require(catalog.first { $0.destination == .robi })
        let harbor = try #require(catalog.first { $0.destination == .harbor })
        let engine = DiscoveryEngine(defaults: defaults, catalog: catalog)
        engine.markUsed(.notificationFeed)
        engine.markUsed(.islands)
        let launch = try sameDay(hour: 9)

        engine.record(.launched, at: launch)
        #expect(engine.queue == [robi.id, harbor.id])
        let shown = launch.addingTimeInterval(robi.calmInterval)
        #expect(engine.advance(at: shown, canPresent: true)?.id == robi.id)
        let ended = shown.addingTimeInterval(ending.visibleFor)
        engine.finish(forever: ending.forever, at: ended)
        #expect(engine.queue == [harbor.id])

        // Radar's calm interval has passed, but the 69-second slot from Robi's tip has not.
        #expect(engine.advance(at: launch.addingTimeInterval(harbor.calmInterval), canPresent: true) == nil)
        let due = shown.addingTimeInterval(DiscoveryEngine.spacing)
        #expect(engine.advance(at: due, canPresent: true)?.id == harbor.id)
        engine.finish(forever: false, at: due)
        // Robi's own signal is spent, so it does not come back in this process.
        #expect(engine.queue.isEmpty)
        #expect(engine.advance(at: due.addingTimeInterval(robi.snoozeInterval), canPresent: true) == nil)
    }

    @Test("Queued launch tips still respect the session and daily caps")
    func launchTipsRespectCaps() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = DiscoveryProposal.catalog.filter { $0.signal == .launched }
        #expect(catalog.map(\.id) == ["notificationFeed", "islands", "robi", "harbor"])
        let launch = try sameDay(hour: 9)

        let engine = DiscoveryEngine(defaults: defaults, catalog: catalog)
        engine.record(.launched, at: launch)
        var now = launch.addingTimeInterval(catalog[0].calmInterval)
        #expect(engine.advance(at: now, canPresent: true)?.id == "notificationFeed")
        engine.finish(forever: false, at: now)
        now = now.addingTimeInterval(DiscoveryEngine.spacing)
        #expect(engine.advance(at: now, canPresent: true)?.id == "islands")
        engine.finish(forever: false, at: now)
        // Two per session: Robi and Radar keep their place but wait for the next launch.
        now = now.addingTimeInterval(DiscoveryEngine.spacing)
        #expect(engine.advance(at: now, canPresent: true) == nil)
        #expect(engine.queue == ["robi", "harbor"])

        // Three per day: the next launch shows Robi, and Radar waits for another day.
        let relaunch = now.addingTimeInterval(600)
        let second = DiscoveryEngine(defaults: defaults, catalog: catalog)
        second.record(.launched, at: relaunch)
        // The feed and Islands queue again but stay snoozed until tomorrow.
        #expect(second.queue == catalog.map(\.id))
        now = relaunch.addingTimeInterval(catalog[2].calmInterval)
        #expect(second.advance(at: now, canPresent: true)?.id == "robi")
        second.finish(forever: false, at: now)
        now = now.addingTimeInterval(DiscoveryEngine.spacing)
        #expect(second.advance(at: now, canPresent: true) == nil)
        #expect(second.queue == ["notificationFeed", "islands", "harbor"])
    }

    /// A fixed local time, so a test's minutes of presentations stay on one calendar day.
    private func sameDay(hour: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: hour)))
    }

    private func proposal(
        id: String,
        threshold: Int,
        calmInterval: TimeInterval = 0,
        snoozeInterval: TimeInterval = 10_000
    ) -> DiscoveryProposal {
        DiscoveryProposal(
            id: id,
            signal: .launched,
            threshold: threshold,
            calmInterval: calmInterval,
            title: .discoveryIslandsTitle,
            message: .discoveryIslandsMessage,
            action: .discoveryIslandsTurnOn,
            destination: .islands,
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
