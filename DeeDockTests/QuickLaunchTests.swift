import AppKit
import Carbon
import Foundation
import Testing
@testable import DeeDock

@MainActor
struct QuickLaunchTests {
    private func app(_ id: String, pinned: Bool = true) -> DockRenderSlot {
        .app(DockItem(reference: DisplayFixtures.app(id), icon: NSImage(), isFavorite: pinned,
                      isRunning: !pinned, isAvailable: true))
    }

    @Test("Numbers count only application icons, in drawing order, and stop after ten")
    func numbering() {
        var entries: [DockRenderSlot] = [.launcher, app("finder"), .gap("drag"), app("safari"),
                                         .group(DockGroupControl(group: .running, count: 2, expanded: true)),
                                         app("notes", pinned: false)]
        entries += (1...12).map { app("extra\($0)", pinned: false) }
        let assignments = QuickLaunchSlots.assignments(for: entries)
        #expect(assignments.count == QuickLaunchSlots.count)
        #expect(assignments.prefix(3).map(\.itemID) == ["finder", "safari", "notes"])
        #expect(assignments.map(\.slot) == Array(1...10))
        #expect(assignments.last?.label == "0")
        #expect(assignments.last?.itemID == "extra7")
        #expect(QuickLaunchSlots.itemID(forSlot: 2, in: entries) == "safari")
    }

    @Test("A slot beyond the dock's apps resolves to nothing")
    func emptySlot() {
        let entries = [app("finder"), app("mail")]
        #expect(QuickLaunchSlots.itemID(forSlot: 3, in: entries) == nil)
        #expect(QuickLaunchSlots.itemID(forSlot: 10, in: entries) == nil)
        #expect(QuickLaunchSlots.assignments(for: [.launcher, .gap("x")]).isEmpty)
    }

    @Test("Number-row key codes map to slots, with 0 as the tenth")
    func keyCodes() {
        #expect(QuickLaunchSlots.slot(forKeyCode: UInt16(kVK_ANSI_1)) == 1)
        #expect(QuickLaunchSlots.slot(forKeyCode: UInt16(kVK_ANSI_9)) == 9)
        #expect(QuickLaunchSlots.slot(forKeyCode: UInt16(kVK_ANSI_0)) == 10)
        #expect(QuickLaunchSlots.slot(forKeyCode: UInt16(kVK_ANSI_Keypad1)) == nil)
        #expect(QuickLaunchSlots.slot(forKeyCode: UInt16(kVK_Space)) == nil)
        #expect((1...10).map(QuickLaunchSlots.label(for:)) == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
    }

    @Test("An absent Quick Launch key stays off, and an explicit on value round-trips app-wide")
    func persistence() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var legacy = try #require(JSONSerialization.jsonObject(with: encoder.encode(DockSettings.defaults)) as? [String: Any])
        legacy.removeValue(forKey: "quickLaunchKeys")
        let decoded = try decoder.decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(!decoded.quickLaunchKeys)
        var enabled = DockSettings.defaults
        enabled.quickLaunchKeys = true
        #expect(try decoder.decode(DockSettings.self, from: encoder.encode(enabled)).quickLaunchKeys)
        #expect(enabled.normalized?.quickLaunchKeys == true)
    }

    @Test("Hints show during Focus Dock or a flash, and never while the feature is off")
    func hintVisibility() {
        let hints = QuickLaunchHints()
        let assignments = QuickLaunchSlots.assignments(for: [app("finder"), app("safari")])
        hints.configure(enabled: false, assignments: assignments)
        hints.setPersistent(true)
        #expect(hints.numbers.isEmpty)
        #expect(hints.label(for: "finder") == nil)

        hints.configure(enabled: true, assignments: assignments)
        #expect(hints.label(for: "safari") == "2")
        hints.setPersistent(false)
        #expect(!hints.isVisible)

        hints.flash(triggered: "safari")
        #expect(hints.isVisible)
        #expect(hints.lastTriggeredID == "safari")
        hints.configure(enabled: false, assignments: assignments)
        #expect(!hints.isFlashing)
        #expect(hints.lastTriggeredID == nil)
        hints.flash(triggered: "finder")
        #expect(!hints.isVisible)
    }

    @Test("A flash ends by itself after its deadline")
    func flashExpires() async throws {
        let hints = QuickLaunchHints()
        hints.configure(enabled: true, assignments: QuickLaunchSlots.assignments(for: [app("finder")]))
        hints.flash(triggered: nil)
        #expect(hints.isFlashing)
        try await Task.sleep(for: QuickLaunchHints.flashDuration + .milliseconds(400))
        #expect(!hints.isFlashing)
        hints.stop()
        #expect(hints.numbers.isEmpty)
    }
}
