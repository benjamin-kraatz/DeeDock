import CoreGraphics
import Foundation
import Testing
@testable import DeeDock

struct HarborLayoutTests {
    private let bounds = CGRect(x: 56, y: 78, width: 1168, height: 560)

    private func group(_ id: String, windows: Int, aspect: CGFloat = 1.5, chips: Int = 0, front: Bool = false) -> HarborLayoutGroup {
        HarborLayoutGroup(id: id,
                          windows: (0..<windows).map { _ in .init(id: UUID(), aspect: aspect) },
                          chips: (0..<chips).map { _ in .init(id: UUID(), width: 140) },
                          headerWidth: 120, isFront: front)
    }

    private func allRects(_ result: HarborLayoutResult) -> [CGRect] {
        Array(result.groups.values) + Array(result.windows.values) + Array(result.chips.values)
    }

    // Twelve such groups no longer fit at the minimum thumbnail height; `overflow` covers that case.
    @Test("Everything stays inside the bounds when it fits", arguments: [1, 3, 6])
    func fitsInsideBounds(groupCount: Int) {
        let groups = (0..<groupCount).map { group("app\($0)", windows: $0 % 4 + 1, chips: $0 % 2) }
        let result = HarborLayout.place(groups, in: bounds)
        #expect(!result.overflows)
        for rect in allRects(result) {
            #expect(bounds.insetBy(dx: -0.5, dy: -0.5).contains(rect))
        }
    }

    @Test("Groups, windows, and chips never overlap one another")
    func noOverlaps() {
        let groups = (0..<7).map { group("app\($0)", windows: $0 % 3 + 1, chips: $0 == 2 ? 2 : 0) }
        let result = HarborLayout.place(groups, in: bounds)
        let cards = Array(result.groups.values)
        for (index, card) in cards.enumerated() {
            for other in cards[(index + 1)...] { #expect(!card.insetBy(dx: 1, dy: 1).intersects(other)) }
        }
        let windows = Array(result.windows.values)
        for (index, window) in windows.enumerated() {
            for other in windows[(index + 1)...] { #expect(!window.insetBy(dx: 1, dy: 1).intersects(other)) }
            #expect(cards.contains { $0.contains(window) })
        }
    }

    @Test("Thumbnails keep each window's aspect ratio")
    func aspectPreserved() {
        let tall = HarborLayoutGroup(id: "pdf", windows: [.init(id: UUID(), aspect: 0.72)], chips: [], headerWidth: 80)
        let wide = HarborLayoutGroup(id: "web", windows: [.init(id: UUID(), aspect: 1.9)], chips: [], headerWidth: 80)
        let result = HarborLayout.place([tall, wide], in: bounds)
        let pdf = result.windows[tall.windows[0].id]!, web = result.windows[wide.windows[0].id]!
        #expect(abs(pdf.width / pdf.height - 0.72) < 0.001)
        #expect(abs(web.width / web.height - 1.9) < 0.001)
        #expect(pdf.height == web.height)
    }

    @Test("The front app's group leads alone with larger thumbnails")
    func frontAppLarge() {
        let groups = [group("front", windows: 3, front: true), group("b", windows: 2), group("c", windows: 1)]
        let result = HarborLayout.place(groups, in: bounds)
        let front = try! #require(result.frontThumbnailHeight)
        #expect(front > result.thumbnailHeight)
        #expect(front <= HarborLayout.Metrics.standard.maximumFrontThumbnail)
        let frontCard = result.groups["front"]!
        for id in ["b", "c"] { #expect(result.groups[id]!.minY >= frontCard.maxY) }
    }

    @Test("Fewer windows never produce smaller thumbnails")
    func moreRoomForFewer() {
        let few = HarborLayout.place([group("a", windows: 2), group("b", windows: 1)], in: bounds)
        let many = HarborLayout.place((0..<10).map { group("app\($0)", windows: 3) }, in: bounds)
        #expect(few.thumbnailHeight >= many.thumbnailHeight)
        #expect(few.thumbnailHeight <= HarborLayout.Metrics.standard.maximumThumbnail)
    }

    @Test("Too many windows overflow at the minimum size instead of shrinking further")
    func overflow() {
        let groups = (0..<40).map { group("app\($0)", windows: 6) }
        let result = HarborLayout.place(groups, in: bounds)
        #expect(result.overflows)
        #expect(result.thumbnailHeight == HarborLayout.Metrics.standard.minimumThumbnail)
        #expect(result.contentHeight > bounds.height)
        #expect(result.windows.count == 240)
    }

    @Test("A group with only minimized windows still gets a card and its chips")
    func chipsOnly() {
        let tucked = group("music", windows: 0, chips: 1)
        let result = HarborLayout.place([group("a", windows: 2), tucked], in: bounds)
        let card = try! #require(result.groups["music"])
        #expect(card.contains(result.chips[tucked.chips[0].id]!))
    }

    @Test("No groups place nothing")
    func empty() {
        #expect(HarborLayout.place([], in: bounds) == HarborLayoutResult())
    }
}
