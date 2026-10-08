import CoreGraphics
import Foundation
import Testing
@testable import DeeDock

struct HarborDiscoveryTests {
    private let safari = HarborRunningApp(id: "com.apple.Safari", name: "Safari", processIdentifier: 10, isHidden: false, isActive: true)
    private let music = HarborRunningApp(id: "com.apple.Music", name: "Musik", processIdentifier: 20, isHidden: true, isActive: false)
    private let session = UUID()

    private func summary(_ pid: pid_t, _ frame: CGRect, title: String? = nil, minimized: Bool = false) -> ApplicationWindowSummary {
        ApplicationWindowSummary(token: ApplicationWindowToken(sessionID: session, id: UUID()), processIdentifier: pid,
                                 title: title, frame: frame, isMinimized: minimized, isMain: false)
    }

    @Test("A window with no on-screen partner is on another Space and is left out")
    func otherSpace() {
        let here = CGRect(x: 100, y: 100, width: 800, height: 500)
        let elsewhere = CGRect(x: 300, y: 200, width: 700, height: 400)
        let windows = HarborDiscoveryProjection.windows(
            apps: [safari], accessibility: [summary(10, here, title: "A"), summary(10, elsewhere, title: "B")],
            screen: [HarborScreenWindow(number: 7, processIdentifier: 10, frame: here, title: "A")], capturable: [7])
        #expect(windows.map(\.title) == ["A"])
        #expect(windows[0].captureID == 7)
        #expect(windows[0].state == .visible)
    }

    @Test("Minimized windows and hidden apps become chips even though they are off screen")
    func tucked() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 500)
        let windows = HarborDiscoveryProjection.windows(
            apps: [safari, music], accessibility: [summary(10, frame, minimized: true), summary(20, frame)],
            screen: [], capturable: [])
        #expect(windows.map(\.state) == [.minimized, .hidden])
        #expect(windows.allSatisfy { $0.captureID == nil && $0.token != nil })
    }

    @Test("Two identical untitled windows are shown but neither gets a thumbnail")
    func ambiguous() {
        let frame = CGRect(x: 0, y: 0, width: 600, height: 400)
        let windows = HarborDiscoveryProjection.windows(
            apps: [safari], accessibility: [summary(10, frame)],
            screen: [HarborScreenWindow(number: 1, processIdentifier: 10, frame: frame),
                     HarborScreenWindow(number: 2, processIdentifier: 10, frame: frame)], capturable: [1, 2])
        #expect(windows.count == 1)
        #expect(windows[0].captureID == nil)
    }

    @Test("Without Screen Recording no window gets a thumbnail")
    func noScreenRecording() {
        let frame = CGRect(x: 0, y: 0, width: 600, height: 400)
        let windows = HarborDiscoveryProjection.windows(
            apps: [safari], accessibility: [summary(10, frame)],
            screen: [HarborScreenWindow(number: 1, processIdentifier: 10, frame: frame)], capturable: nil)
        #expect(windows.count == 1)
        #expect(windows[0].captureID == nil)
    }

    @Test("Without Accessibility the on-screen list supplies app-level cards in front-to-back order")
    func noAccessibility() {
        let windows = HarborDiscoveryProjection.windows(
            apps: [safari], accessibility: nil,
            screen: [HarborScreenWindow(number: 5, processIdentifier: 10, frame: CGRect(x: 0, y: 0, width: 600, height: 400), title: "Front"),
                     HarborScreenWindow(number: 6, processIdentifier: 99, frame: CGRect(x: 0, y: 0, width: 600, height: 400)),
                     HarborScreenWindow(number: 8, processIdentifier: 10, frame: CGRect(x: 0, y: 0, width: 20, height: 20)),
                     HarborScreenWindow(number: 9, processIdentifier: 10, frame: CGRect(x: 50, y: 50, width: 500, height: 300), title: "Back")],
            capturable: [5, 9])
        #expect(windows.map(\.title) == ["Front", "Back"])
        #expect(windows.allSatisfy { $0.token == nil })
        #expect(windows.map(\.stackOrder) == [0, 3])
    }

    @Test("Windows go to the display they overlap most, including negative origins")
    func displayAssignment() {
        let displays = ["left": CGRect(x: -1440, y: 0, width: 1440, height: 900),
                        "main": CGRect(x: 0, y: 0, width: 1728, height: 1117)]
        #expect(HarborGrouping.display(for: CGRect(x: -400, y: 100, width: 500, height: 400), in: displays) == "left")
        #expect(HarborGrouping.display(for: CGRect(x: -100, y: 100, width: 500, height: 400), in: displays) == "main")
        #expect(HarborGrouping.display(for: CGRect(x: -3000, y: 100, width: 500, height: 400), in: displays) == "left")
    }

    @Test("Groups follow their frontmost window, and apps with only chips come last")
    func groupOrder() {
        func window(_ app: String, _ order: Int, _ state: HarborWindowState = .visible) -> HarborWindow {
            HarborWindow(id: UUID(), appID: app, processIdentifier: 1, title: nil, frame: CGRect(x: 10, y: 10, width: 300, height: 200),
                         state: state, token: nil, captureID: nil, stackOrder: order)
        }
        let apps = [safari, music, HarborRunningApp(id: "finder", name: "Finder", processIdentifier: 3, isHidden: false, isActive: false)]
        let groups = HarborGrouping.groups(windows: [window("finder", 4), window("com.apple.Safari", 1), window("com.apple.Music", 9, .hidden),
                                                     window("com.apple.Safari", 6)],
                                           apps: apps, displayBounds: ["d": CGRect(x: 0, y: 0, width: 1000, height: 800)], displayID: "d")
        #expect(groups.map(\.id) == ["com.apple.Safari", "finder", "com.apple.Music"])
        #expect(groups[0].windows.map(\.stackOrder) == [1, 6])
        #expect(groups[2].tucked.count == 1)
    }

    @Test("Search needs every word, ignores case and accents, and an app-name match keeps the whole group")
    func search() {
        let windows = ["Küste und Licht.pdf", "Hausentwurf.pdf"].enumerated().map { index, title in
            HarborWindow(id: UUID(), appID: "preview", processIdentifier: 1, title: title, frame: .zero, state: .visible,
                         token: nil, captureID: nil, stackOrder: index)
        }
        let groups = [HarborAppGroup(id: "preview", name: "Vorschau", windows: windows, tucked: [])]
        #expect(HarborGrouping.filter(groups, query: "kuste licht").first?.windows.count == 1)
        #expect(HarborGrouping.filter(groups, query: "VORSCHAU").first?.windows.count == 2)
        #expect(HarborGrouping.filter(groups, query: "kuste haus").isEmpty)
        #expect(HarborGrouping.filter(groups, query: "  ").first?.windows.count == 2)
    }

    @Test("Arrow keys move to the nearest window in that direction")
    func navigation() {
        let a = UUID(), b = UUID(), c = UUID()
        let origin = CGRect(x: 0, y: 0, width: 100, height: 60)
        let candidates = [(a, CGRect(x: 140, y: 0, width: 100, height: 60)),
                          (b, CGRect(x: 0, y: 120, width: 100, height: 60)),
                          (c, CGRect(x: 300, y: 10, width: 100, height: 60))]
        #expect(HarborNavigation.next(from: origin, direction: .right, candidates: candidates) == a)
        #expect(HarborNavigation.next(from: origin, direction: .down, candidates: candidates) == b)
        #expect(HarborNavigation.next(from: origin, direction: .left, candidates: candidates) == nil)
    }
}
