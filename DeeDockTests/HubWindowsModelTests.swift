import CoreGraphics
import Foundation
import Testing
@testable import DeeDock

struct HubWindowsGroupingTests {
    private let safari = HarborRunningApp(id: "com.apple.Safari", name: "Safari", processIdentifier: 10, isHidden: false, isActive: true)
    private let notes = HarborRunningApp(id: "com.apple.Notes", name: "Notizen", processIdentifier: 20, isHidden: false, isActive: false)
    private let music = HarborRunningApp(id: "com.apple.Music", name: "Musik", processIdentifier: 30, isHidden: true, isActive: false)

    private func window(_ app: HarborRunningApp, _ title: String?, order: Int, state: HarborWindowState = .visible,
                        capture: CGWindowID? = nil, frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 500)) -> HarborWindow {
        HarborWindow(id: UUID(), appID: app.id, processIdentifier: app.processIdentifier, title: title, frame: frame,
                     state: state, token: nil, captureID: capture, stackOrder: order)
    }

    @Test("Apps follow their frontmost on-screen window; apps with only tucked windows come last in running order")
    func appOrder() {
        let groups = HubWindowsGrouping.groups(
            windows: [window(music, "Album", order: 9, state: .hidden), window(notes, "List", order: 1),
                      window(safari, "Docs", order: 3), window(safari, "Home", order: 0)],
            apps: [safari, notes, music])
        #expect(groups.map(\.id) == [safari.id, notes.id, music.id])
        #expect(groups[0].windows.map(\.window.title) == ["Home", "Docs"])
        #expect(groups[2].name == "Musik")
    }

    @Test("Inside a group, on-screen windows come first, then minimized, then hidden")
    func windowOrder() {
        let groups = HubWindowsGrouping.groups(
            windows: [window(safari, "Min", order: 0, state: .minimized), window(safari, "Back", order: 5),
                      window(safari, "Front", order: 2)],
            apps: [safari])
        #expect(groups[0].windows.map(\.window.title) == ["Front", "Back", "Min"])
    }

    @Test("Windows of apps that are not running regular apps are dropped")
    func unknownApp() {
        let stranger = HarborRunningApp(id: "x", name: "X", processIdentifier: 99, isHidden: false, isActive: false)
        let groups = HubWindowsGrouping.groups(windows: [window(stranger, "Panel", order: 0)], apps: [safari])
        #expect(groups.isEmpty)
    }

    @Test("Stable IDs survive rediscovery and stay unique for identical untitled windows")
    func stableIDs() {
        let first = HubWindowsGrouping.groups(windows: [window(safari, "A", order: 0, capture: 42)], apps: [safari])
        let second = HubWindowsGrouping.groups(windows: [window(safari, "A", order: 3, capture: 42)], apps: [safari])
        #expect(first[0].windows[0].id == second[0].windows[0].id)

        let twins = HubWindowsGrouping.groups(windows: [window(safari, nil, order: 0), window(safari, nil, order: 1)],
                                              apps: [safari])
        let ids = twins[0].windows.map(\.id)
        #expect(Set(ids).count == 2)
    }

    @Test("Every query word must match the title or app name, ignoring case and diacritics")
    func filterWords() {
        let groups = HubWindowsGrouping.groups(
            windows: [window(safari, "Apple Developer", order: 0), window(safari, "Café menu", order: 1),
                      window(notes, "Groceries", order: 2)],
            apps: [safari, notes])
        #expect(HubWindowsGrouping.filter(groups, query: "  ").map(\.id) == [safari.id, notes.id])
        let cafe = HubWindowsGrouping.filter(groups, query: "safari CAFE")
        #expect(cafe.map(\.id) == [safari.id])
        #expect(cafe[0].windows.map(\.window.title) == ["Café menu"])
        #expect(HubWindowsGrouping.filter(groups, query: "notizen")[0].windows.count == 1)
        #expect(HubWindowsGrouping.filter(groups, query: "nothing").isEmpty)
    }
}

struct HubWindowsNavigationTests {
    private let order = ["a", "b", "c", "d"]
    // a b c on the first line, d below a.
    private let frames: [String: CGRect] = [
        "a": CGRect(x: 0, y: 0, width: 200, height: 150), "b": CGRect(x: 212, y: 0, width: 200, height: 150),
        "c": CGRect(x: 424, y: 0, width: 200, height: 150), "d": CGRect(x: 0, y: 200, width: 200, height: 150),
    ]

    @Test("The first arrow selects the first card")
    func firstSelection() {
        #expect(HubWindowsNavigation.next(from: nil, direction: .down, order: order, frames: frames) == "a")
        #expect(HubWindowsNavigation.next(from: "gone", direction: .right, order: order, frames: frames) == "a")
        #expect(HubWindowsNavigation.next(from: nil, direction: .right, order: [], frames: [:]) == nil)
    }

    @Test("Left and right follow reading order and stop at the ends")
    func horizontal() {
        #expect(HubWindowsNavigation.next(from: "c", direction: .right, order: order, frames: frames) == "d")
        #expect(HubWindowsNavigation.next(from: "d", direction: .right, order: order, frames: frames) == "d")
        #expect(HubWindowsNavigation.next(from: "a", direction: .left, order: order, frames: frames) == "a")
    }

    @Test("Up and down pick the nearest card on the next line, or stay put")
    func vertical() {
        #expect(HubWindowsNavigation.next(from: "b", direction: .down, order: order, frames: frames) == "d")
        #expect(HubWindowsNavigation.next(from: "d", direction: .up, order: order, frames: frames) == "a")
        #expect(HubWindowsNavigation.next(from: "a", direction: .up, order: order, frames: frames) == "a")
    }
}

@MainActor
struct HubWindowsCaptureBudgetTests {
    @Test("A large window is captured just big enough to fill a lifted card")
    func largeWindow() {
        let pixels = HubWindowsModel.capturePixels(for: CGSize(width: 2000, height: 1000), scale: 2)
        // The card's height ratio wins for a wide window: 124 × 1.1 × 2 ≈ 273 pixels tall.
        #expect(pixels.height == 273)
        #expect(pixels.width >= HubWindowCardMetrics.thumbnailSize.width * 1.1 * 2)
    }

    @Test("A small window is never upscaled")
    func smallWindow() {
        let pixels = HubWindowsModel.capturePixels(for: CGSize(width: 120, height: 80), scale: 2)
        #expect(pixels == CGSize(width: 240, height: 160))
    }
}
