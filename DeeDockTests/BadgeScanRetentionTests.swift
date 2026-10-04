import Foundation
import Testing
@testable import DeeDock

@MainActor
struct BadgeScanRetentionTests {
    private let mail = "/Applications/Mail.app"

    @Test("A failed scan keeps the last snapshot within the grace period, then clears")
    func failedScanRetention() {
        var retention = BadgeScanRetention()
        let start = ContinuousClock.now
        let snapshot: [String: BadgeObservation] = [mail: .count(3)]
        #expect(retention.resolve(snapshot, at: start) == .update(snapshot))
        #expect(retention.resolve(nil, at: start.advanced(by: .seconds(5))) == .retain)
        #expect(retention.resolve(nil, at: start.advanced(by: .seconds(10))) == .retain)
        #expect(retention.resolve(nil, at: start.advanced(by: BadgeScanRetention.gracePeriod)) == .update([:]))
        // Once unavailable, a later failure must not revive the old snapshot.
        #expect(retention.resolve(nil, at: start.advanced(by: .seconds(16))) == .update([:]))
        #expect(retention.resolve(snapshot, at: start.advanced(by: .seconds(20))) == .update(snapshot))
        #expect(retention.resolve(nil, at: start.advanced(by: .seconds(25))) == .retain)
    }

    @Test("A successful scan without badges clears immediately")
    func emptySuccessClears() {
        var retention = BadgeScanRetention()
        let start = ContinuousClock.now
        _ = retention.resolve([mail: .count(3)], at: start)
        #expect(retention.resolve([:], at: start.advanced(by: .seconds(1))) == .update([:]))
    }

    @Test("A failure before any successful scan has nothing to retain")
    func failureWithoutSnapshot() {
        var retention = BadgeScanRetention()
        #expect(retention.resolve(nil, at: .now) == .update([:]))
    }

    private func memory(_ suite: String) throws -> (BadgeMemoryStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = BadgeMemoryStore(defaults: defaults)
        store.start(session: nil)
        store.setCollectFocus(true)
        return (store, defaults)
    }

    /// Seeds a tracked app at 4, then starts collecting a running session at `base + 2`.
    private func collecting(_ store: BadgeMemoryStore, base: Date) -> FocusSession {
        store.observe([mail: .count(3)], session: nil, at: base)
        store.observe([mail: .count(4)], session: nil, at: base.addingTimeInterval(1))
        let session = FocusSession(id: UUID(), modeID: UUID(), modeName: "Focus", duration: 1500,
                                   remainingWhenPaused: 1500, deadline: base.addingTimeInterval(1500),
                                   phase: .running)
        store.observe([mail: .count(4)], session: session, at: base.addingTimeInterval(2))
        return session
    }

    @Test("A retained gap marks the digest incomplete without adding unknown transitions")
    func retainedGapKeepsHistory() throws {
        let suite = "BadgeGap.\(UUID().uuidString)"
        let (store, defaults) = try memory(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let base = Date()
        let session = collecting(store, base: base)
        #expect(store.document.active?.incomplete == false)
        let history = store.document.apps[mail]?.changes.map(\.value)
        #expect(history == [.count(4)])

        store.markGap(session: session, at: base.addingTimeInterval(7), scanStarted: base.addingTimeInterval(6))
        store.observe([mail: .count(4)], session: session, at: base.addingTimeInterval(12),
                      scanStarted: base.addingTimeInterval(11))

        #expect(store.current == [mail: .count(4)])
        #expect(store.document.apps[mail]?.changes.map(\.value) == history)
        let row = try #require(store.document.active?.rows[mail])
        #expect(row.changes == 0)
        #expect(!row.hasGap)
        #expect(store.document.active?.incomplete == true)
    }

    @Test("A failed scan begun before the session started does not mark its digest")
    func gapBeforeBoundary() throws {
        let suite = "BadgeGapBoundary.\(UUID().uuidString)"
        let (store, defaults) = try memory(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let base = Date()
        let session = collecting(store, base: base)
        store.markGap(session: session, at: base.addingTimeInterval(3), scanStarted: base.addingTimeInterval(1))
        #expect(store.document.active?.incomplete == false)
    }
}
