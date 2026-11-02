import CoreGraphics
import Foundation
import Testing
@testable import DeeDock

/// The labelled window and where the prompt panel goes.
@MainActor
struct AppHealthLabelWindowTests {
    private let moment = Date(timeIntervalSince1970: 1_793_000_000)

    @Test("A prompt labels the five minutes before it appeared")
    func promptWindow() {
        let window = AppHealthLabelWindow.prompt(shownAt: moment)
        #expect(window.start == moment.addingTimeInterval(-300))
        #expect(window.end == moment)
    }

    @Test("A manual label ends when the app was picked")
    func manualWindow() {
        let window = AppHealthLabelWindow.manual(pickedAt: moment)
        #expect(window.start == moment.addingTimeInterval(-300))
        #expect(window.end == moment)
    }

    @Test("A label record carries the window as Unix seconds")
    func labelRecordWindow() {
        let window = AppHealthLabelWindow.prompt(shownAt: moment)
        let record = AppHealthLabelRecord(id: UUID(), app: "a", answer: .expected, from: window.start, to: window.end,
                                          source: .prompt, responseSeconds: 4.2)
        #expect(record.from == 1_793_000_000 - 300)
        #expect(record.to == 1_793_000_000)
    }

    @Test("A tile prompt sits above a bottom dock's tile, clear of the tile")
    func tilePlacement() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let tile = CGRect(x: 700, y: 10, width: 48, height: 48)
        let anchor = AppHealthAnchor(kind: .tile, rect: tile, edge: .bottom, visibleFrame: visible)
        let frame = AppHealthPromptPlacement.frame(size: CGSize(width: 340, height: 150), anchor: anchor)
        #expect(frame.size == CGSize(width: 340, height: 150))
        #expect(frame.midX == tile.midX)
        #expect(frame.minY >= tile.maxY + AppHealthPromptPlacement.gap)
    }

    @Test("A screen prompt grows up and to the left of the corner, inside the visible frame")
    func screenPlacement() {
        // A secondary display left of the primary one, with a negative origin.
        let visible = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let anchor = AppHealthAnchor.screen(visibleFrame: visible)
        let frame = AppHealthPromptPlacement.frame(size: CGSize(width: 340, height: 150), anchor: anchor)
        #expect(frame.maxX <= visible.maxX - DockPopoverGeometry.margin)
        #expect(frame.minY >= visible.minY + DockPopoverGeometry.margin)
        #expect(frame.minX < 0)
    }
}
