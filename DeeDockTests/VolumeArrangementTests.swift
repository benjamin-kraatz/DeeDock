import Foundation
import Testing
@testable import DeeDock

@MainActor
struct VolumeArrangementTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func info(_ id: String, name: String? = nil, kind: VolumeKind = .removable) -> VolumeInfo {
        VolumeInfo(volumeID: id, url: URL(fileURLWithPath: "/Volumes/\(id)"), name: name ?? id, kind: kind)
    }

    private func arrangement(_ ids: [String]) -> VolumeArrangement {
        var arrangement = VolumeArrangement()
        arrangement.remember(ids.map { info($0) }, previouslyMounted: [], at: start)
        return arrangement
    }

    @Test("New drives join at the end, and a returning drive keeps its place")
    func arrivalOrder() {
        var arrangement = arrangement(["a", "b"])
        arrangement.remember([info("b")], previouslyMounted: ["a", "b"], at: start + 60)
        arrangement.remember([info("c"), info("a", name: "Renamed"), info("b")], previouslyMounted: ["b"], at: start + 120)
        #expect(arrangement.entries.map(\.volumeID) == ["a", "b", "c"])
        #expect(arrangement.entries[0].name == "Renamed")
        #expect(arrangement.arranged([info("c"), info("b"), info("x"), info("a")], id: \.volumeID).map(\.volumeID)
                == ["a", "b", "c", "x"])
    }

    @Test("Last seen marks arrivals and departures, not drives that stayed mounted")
    func lastSeen() {
        var arrangement = arrangement(["a", "b"])
        arrangement.remember([info("a"), info("b"), info("c")], previouslyMounted: ["a", "b"], at: start + 60)
        #expect(arrangement.entries.map(\.lastSeen) == [start, start, start + 60])
        arrangement.remember([info("a"), info("c")], previouslyMounted: ["a", "b", "c"], at: start + 120)
        #expect(arrangement.entries.map(\.lastSeen) == [start, start + 120, start + 60])
    }

    @Test("Moves use gap indices within a visible subset and keep other drives' neighbors",
          arguments: [
            ("a", 2, ["b", "c", "a", "d"]),
            ("c", 0, ["c", "a", "b", "d"]),
            ("a", 1, ["b", "a", "c", "d"]),
            ("b", 99, ["a", "c", "b", "d"]),
          ])
    func move(id: String, index: Int, expected: [String]) {
        var arrangement = arrangement(["a", "b", "c", "d"])
        // "d" is hidden or disconnected, so it is outside the sequence the dock or list shows.
        arrangement.move(id, to: index, within: ["a", "b", "c"])
        #expect(arrangement.entries.map(\.volumeID) == expected)
    }

    @Test("Hiding keeps the drive's place and reports whether anything changed")
    func hiding() {
        var arrangement = arrangement(["a", "b"])
        let hid = arrangement.setHidden("a", true)
        let hidAgain = arrangement.setHidden("a", true)
        let hidMissing = arrangement.setHidden("missing", true)
        #expect(hid && !hidAgain && !hidMissing)
        #expect(arrangement.isHidden("a") && !arrangement.isHidden("b"))
        #expect(arrangement.entries.map(\.volumeID) == ["a", "b"])
    }

    @Test("Pruning forgets the stalest disconnected drives but never hidden or mounted ones")
    func pruning() {
        var arrangement = VolumeArrangement()
        let ids = (0..<VolumeArrangement.capacity).map { "old\($0)" }
        for (offset, id) in ids.enumerated() {
            arrangement.remember([info(id)], previouslyMounted: [], at: start + Double(offset))
            arrangement.remember([], previouslyMounted: [id], at: start + Double(offset))
        }
        arrangement.setHidden("old0", true)
        arrangement.remember([info("new")], previouslyMounted: [], at: start + 1_000)
        #expect(arrangement.entries.count == VolumeArrangement.capacity)
        #expect(arrangement.entries.contains { $0.volumeID == "old0" })
        #expect(!arrangement.entries.contains { $0.volumeID == "old1" })
        #expect(arrangement.entries.last?.volumeID == "new")
    }

    @Test("The store persists order and hidden drives, and edits notify the docks")
    func persistence() throws {
        let suite = "VolumeArrangementTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = VolumeArrangementStore(defaults: defaults)
        var changes = 0
        store.didChange = { changes += 1 }
        store.remember([info("a"), info("b")], previouslyMounted: [])
        #expect(changes == 0)
        store.move("b", to: 0, within: ["a", "b"])
        store.setHidden("a", true)
        store.setHidden("a", true)
        #expect(changes == 2)
        let reloaded = VolumeArrangementStore(defaults: defaults)
        #expect(reloaded.entries.map(\.volumeID) == ["b", "a"])
        #expect(reloaded.isHidden("a"))
    }
}
