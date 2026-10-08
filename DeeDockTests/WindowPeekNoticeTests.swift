import CoreGraphics
import Foundation
import Testing
@testable import DeeDock

@MainActor
struct WindowPeekNoticeTests {
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test("The spring starts at the label, overshoots a little, and settles on the strip")
    func spring() {
        #expect(WindowPeekNoticeMotion.progress(at: 0) == 0)
        #expect(WindowPeekNoticeMotion.progress(at: -1) == 0)
        let peak = stride(from: 0.0, to: 1, by: 0.002).map(WindowPeekNoticeMotion.progress(at:)).max() ?? 0
        #expect(peak > 1 && peak < 1.05)
        // The mockup's tuning: about half a second from hand-off to rest.
        #expect((0.45...0.6).contains(WindowPeekNoticeMotion.settleTime))
        #expect(WindowPeekNoticeMotion.glintStart < WindowPeekNoticeMotion.settleTime)
        #expect(abs(WindowPeekNoticeMotion.progress(at: WindowPeekNoticeMotion.settleTime) - 1) <= 0.003)
        #expect(WindowPeekNoticeMotion.duration >= WindowPeekNoticeMotion.settleTime)
    }

    @Test("The flight begins on the label, ends on the strip, and bows away from the dock")
    func path() {
        let label = CGRect(x: 100, y: 400, width: 220, height: 40)
        let strip = CGRect(x: 400, y: 380, width: 260, height: 58)
        #expect(WindowPeekNoticeMotion.flightFrame(from: label, to: strip, progress: 0) == label)
        #expect(WindowPeekNoticeMotion.flightFrame(from: label, to: strip, progress: 1) == strip)
        // Mostly horizontal travel in top-left space bows upward, to a smaller y than the chord.
        let middle = WindowPeekNoticeMotion.flightFrame(from: label, to: strip, progress: 0.5)
        #expect(middle.midY < (label.midY + strip.midY) / 2 - 20)
        // Overshoot moves the frame past the strip but never grows it past the strip's size.
        let over = WindowPeekNoticeMotion.flightFrame(from: label, to: strip, progress: 1.03)
        #expect(over.minX > strip.minX)
        #expect(over.size == strip.size)
    }

    @Test("Growth keeps the panel's dock side fixed and stops at the usable frame")
    func growth() {
        let bottom = WindowPeekPlacement(frame: CGRect(x: 500, y: 100, width: 300, height: 260), edge: .bottom)
        let grown = WindowPeekGeometry.extended(bottom, by: 60, within: visible)
        #expect(grown.frame.minY == 100)
        #expect(grown.frame.height == 320)

        let top = WindowPeekPlacement(frame: CGRect(x: 500, y: 500, width: 300, height: 260), edge: .top)
        let down = WindowPeekGeometry.extended(top, by: 60, within: visible)
        #expect(down.frame.maxY == 760)
        #expect(down.frame.height == 320)

        let tall = WindowPeekPlacement(frame: CGRect(x: 500, y: 100, width: 300, height: 760), edge: .bottom)
        let capped = WindowPeekGeometry.extended(tall, by: 200, within: visible)
        #expect(capped.frame.maxY == visible.maxY - WindowPeekGeometry.screenMargin)
        #expect(WindowPeekGeometry.extended(bottom, by: 0, within: visible) == bottom)
    }

    @Test("Only a new badge with a banner becomes a notice, with the sender split from the message")
    func notice() {
        let entry = NotificationFeedEntry(id: "1", appName: "WhatsApp", title: " Mike Hoffmann ",
                                          subtitle: nil, body: "Good Morning", arrivedAt: .now)
        let badge = DockTooltipBadge(summary: "1 new", isNew: true, banner: "Mike Hoffmann: Good Morning", entry: entry)
        let notice = WindowPeekNotice(badge: badge, appName: "WhatsApp")
        #expect(notice == WindowPeekNotice(summary: "1 new", sender: "Mike Hoffmann", message: "Good Morning"))
        #expect(notice?.spoken == "Mike Hoffmann: Good Morning")

        let untitled = NotificationFeedEntry(id: "2", appName: "WhatsApp", title: nil,
                                             subtitle: nil, body: "Ping", arrivedAt: .now)
        #expect(WindowPeekNotice(badge: DockTooltipBadge(summary: "New", isNew: true, banner: "Ping", entry: untitled),
                                 appName: "WhatsApp")?.sender == "WhatsApp")

        #expect(WindowPeekNotice(badge: DockTooltipBadge(summary: "3", isNew: false, banner: nil), appName: "Mail") == nil)
        #expect(WindowPeekNotice(badge: DockTooltipBadge(summary: "2 new", isNew: true, banner: nil), appName: "Mail") == nil)
    }
}
