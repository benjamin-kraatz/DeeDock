import CoreGraphics
import Foundation
import Testing
@testable import DeeDock

/// Flix Pick's placement beside a picker and its ranking.
struct FlixPickTests {
    @Test func railFlipsLeftWhenThePickerReachesTheScreenEdge() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let picker = CGRect(x: 1440 - 760, y: 200, width: 740, height: 440)
        let side = FlixPickPlacement.side(picker: picker, visible: visible)
        #expect(side == .left)
        let closed = FlixPickPlacement.body(picker: picker, visible: visible, rows: 5, open: false, side: side)
        let open = FlixPickPlacement.body(picker: picker, visible: visible, rows: 5, open: true, side: side)
        // The edge next to the picker stays put while the rail opens away from it.
        #expect(closed.maxX == picker.minX - FlixPickPlacement.gap)
        #expect(open.maxX == closed.maxX)
        #expect(open.maxY == picker.maxY - FlixPickPlacement.topInset)
    }

    @Test func picksInThisAppOutrankAFileOpenedAMinuteAgo() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let picked = FlixPickSignals(pickedCount: 2, lastPicked: now.addingTimeInterval(-3 * 86_400),
                                     activity: .opened, date: now.addingTimeInterval(-3 * 86_400))
        let fresh = FlixPickSignals(activity: .opened, date: now.addingTimeInterval(-60))
        let ranked = FlixPickRanker.rank([(id: "fresh", signals: fresh), (id: "picked", signals: picked)], now: now)
        #expect(ranked.map(\.id) == ["picked", "fresh"])
        #expect(ranked.first?.score.strongest == .picked(2))
    }
}
