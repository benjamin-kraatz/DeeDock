import CoreGraphics
import Foundation
import Testing
@testable import DeeDock

/// Robi has to sit exactly on the window's top edge, fall back to hanging inside when nothing fits
/// above, and keep up with a dragged title bar without overshooting the menu bar.
@Suite("Robi placement and drag prediction")
struct RobiGeometryTests {
    /// A 1440×900 primary display with a 24 pt menu bar, AppKit coordinates.
    private let display = RobiScreenSpace.Display(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                                  visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 876))

    @Test("A window with room above gets the tab above it, its bottom one point into the window")
    func placesAbove() {
        let window = CGRect(x: 200, y: 300, width: 800, height: 400)
        #expect(RobiLayout.placement(window: window, isFullScreen: false, display: display) == .above)
        let size = CGSize(width: 132, height: RobiMetrics.tabHeight + RobiMetrics.shadowMargin)
        let frame = RobiLayout.panelFrame(window: window, placement: .above, size: size, display: display)
        #expect(frame.midX == window.midX)
        #expect(frame.maxY == window.maxY - 1 + RobiMetrics.tabHeight + RobiMetrics.shadowMargin)
        #expect(frame.minY == window.maxY - 1)
    }

    @Test("A window under the menu bar, or in full screen, gets the tab hanging inside")
    func placesInside() {
        let maximized = CGRect(x: 0, y: 0, width: 1440, height: 876)
        #expect(RobiLayout.placement(window: maximized, isFullScreen: false, display: display) == .inside)
        let window = CGRect(x: 200, y: 100, width: 800, height: 400)
        #expect(RobiLayout.placement(window: window, isFullScreen: true, display: display) == .inside)
        let frame = RobiLayout.panelFrame(window: maximized, placement: .inside, size: CGSize(width: 132, height: 52), display: display)
        #expect(frame.maxY == maximized.maxY)
    }

    @Test("A wide prompt bar stays on the window's display when the window hangs off its edge")
    func clampsToDisplay() {
        let window = CGRect(x: 1200, y: 300, width: 600, height: 400)
        let size = CGSize(width: RobiMetrics.barWidth + 2 * RobiMetrics.sideMargin, height: 400)
        let frame = RobiLayout.panelFrame(window: window, placement: .above, size: size, display: display)
        #expect(frame.maxX <= display.frame.maxX)
        #expect(RobiLayout.anchorX(window: window, display: display) == (1200 + 1440) / 2)
    }

    @Test("Top-left and AppKit rects convert around the primary display's height")
    func convertsCoordinates() {
        let space = RobiScreenSpace(primaryHeight: 900, displays: [display])
        let appKit = space.appKitRect(fromTopLeft: CGRect(x: 100, y: 50, width: 300, height: 200))
        #expect(appKit == CGRect(x: 100, y: 650, width: 300, height: 200))
        #expect(space.topLeftPoint(fromAppKit: CGPoint(x: 10, y: 890)) == CGPoint(x: 10, y: 10))
        #expect(space.topLimit(at: CGPoint(x: 100, y: 400)) == 24)
    }

    @Test("Only a drag that starts in the title band is predicted")
    func startsInTitleBand() {
        let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
        #expect(RobiDragPrediction(pointer: CGPoint(x: 300, y: 110), frame: frame) != nil)
        #expect(RobiDragPrediction(pointer: CGPoint(x: 300, y: 300), frame: frame) == nil)
        #expect(RobiDragPrediction(pointer: CGPoint(x: 50, y: 110), frame: frame) == nil)
    }

    @Test("The prediction follows the pointer but stops at the menu bar like the window server")
    func followsPointer() throws {
        var prediction = try #require(RobiDragPrediction(pointer: CGPoint(x: 300, y: 110), frame: CGRect(x: 100, y: 100, width: 600, height: 400)))
        #expect(prediction.frame(pointer: CGPoint(x: 360, y: 150), topLimit: 24) == CGRect(x: 160, y: 140, width: 600, height: 400))
        #expect(prediction.frame(pointer: CGPoint(x: 360, y: 20), topLimit: 24).minY == 24)
    }

    @Test("A drag that leaves the window where it was is recognized as not a window drag")
    func detectsStall() throws {
        let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
        var prediction = try #require(RobiDragPrediction(pointer: CGPoint(x: 300, y: 110), frame: frame))
        for step in 1...RobiDragPrediction.verificationEvents {
            _ = prediction.frame(pointer: CGPoint(x: 300 + CGFloat(step) * 5, y: 110), topLimit: 24)
        }
        #expect(prediction.isStalled(actual: frame))
        #expect(!prediction.isStalled(actual: frame.offsetBy(dx: 20, dy: 0)))
    }

    // MARK: Moving the tab

    /// How far the tab's centre stays from a side of the window it is dragged towards.
    private var reach: CGFloat { RobiMetrics.tabWidth / 2 + RobiMetrics.edgeInset }

    @Test("A dragged tab reaches the corners but keeps its whole width over the window")
    func clampsToCorners() {
        let window = CGRect(x: 200, y: 300, width: 800, height: 400)
        #expect(RobiLayout.tabX(window: window, position: 0, display: display) == window.minX + reach)
        #expect(RobiLayout.tabX(window: window, position: 1, display: display) == window.maxX - reach)
        #expect(RobiLayout.tabX(window: window, position: -3, display: display) == window.minX + reach)
        #expect(RobiLayout.tabX(window: window, position: nil, display: display) == window.midX)
        let size = CGSize(width: RobiMetrics.tabWidth + 2 * RobiMetrics.sideMargin, height: RobiMetrics.tabHeight + RobiMetrics.shadowMargin)
        let frame = RobiLayout.panelFrame(window: window, placement: .above, size: size, display: display, position: 0)
        #expect(frame.midX - RobiMetrics.tabWidth / 2 >= window.minX + RobiMetrics.edgeInset)
    }

    @Test("A window barely wider than the tab keeps it near the middle, and a narrower one pins it there")
    func clampsNarrowWindow() {
        let narrow = CGRect(x: 200, y: 300, width: 240, height: 400)
        let track = RobiLayout.tabTrack(window: narrow, display: display)
        #expect(track == (narrow.minX + reach)...(narrow.maxX - reach))
        #expect(RobiLayout.tabX(window: narrow, position: 0.9, display: display) == narrow.maxX - reach)
        let tiny = CGRect(x: 200, y: 300, width: 120, height: 400)
        #expect(RobiLayout.tabX(window: tiny, position: 0, display: display) == tiny.midX)
        #expect(RobiLayout.tabX(window: tiny, position: 1, display: display) == tiny.midX)
    }

    @Test("A window partly off its display keeps the tab on the part that shows")
    func clampsToVisibleEdge() {
        let window = CGRect(x: 1200, y: 300, width: 600, height: 400)
        #expect(RobiLayout.tabX(window: window, position: 1, display: display) == display.frame.maxX - reach)
        #expect(RobiLayout.tabX(window: window, position: 0, display: display) == window.minX + reach)
        let stored = RobiLayout.position(forTabX: 5_000, window: window, display: display)
        #expect(abs(stored - Double((display.frame.maxX - reach - window.minX) / window.width)) < 1e-9)
    }

    @Test("A pointer position maps back to the position that puts the tab under it")
    func invertsPointer() {
        let window = CGRect(x: 200, y: 300, width: 800, height: 400)
        let position = RobiLayout.position(forTabX: 440, window: window, display: display)
        #expect(abs(position - 0.3) < 1e-9)
        #expect(abs(RobiLayout.tabX(window: window, position: position, display: display) - 440) < 1e-9)
        // Past the track, the position stored is the one at its end.
        let past = RobiLayout.position(forTabX: -500, window: window, display: display)
        #expect(RobiLayout.tabX(window: window, position: past, display: display) == window.minX + reach)
    }

    @Test("Dragging past the end of the track rubber-bands, never further than its limit")
    func rubberBands() {
        #expect(RobiLayout.rubberBand(0) == 0)
        #expect(RobiLayout.rubberBand(4) > 0 && RobiLayout.rubberBand(4) < 4)
        #expect(RobiLayout.rubberBand(-4) == -RobiLayout.rubberBand(4))
        #expect(RobiLayout.rubberBand(10_000) < RobiMetrics.rubberBandLimit)
        #expect(RobiTabSpring.remaining(after: 0) == 1)
        #expect(RobiTabSpring.remaining(after: RobiTabSpring.duration) == 0)
    }

    @Test("A press is a click until it moves past the drag threshold")
    func tellsClickFromDrag() {
        let press = RobiFacePress(start: CGPoint(x: 500, y: 800), canDrag: true, grip: 0)
        #expect(!press.hasLeftClickDistance(CGPoint(x: 503, y: 801)))
        #expect(press.hasLeftClickDistance(CGPoint(x: 505, y: 800)))
    }
}

@Suite("Robi settings")
struct RobiSettingsTests {
    @Test("Robi is opt-in, answers on device, and keeps its shortcut on by default")
    func defaults() {
        let settings = RobiSettings()
        #expect(!settings.isEnabled)
        #expect(settings.answerModel == .onDevice)
        #expect(settings.claudeEffort == .medium)
        #expect(settings.shortcutEnabled)
        #expect(settings.excludedBundleIdentifiers.isEmpty)
    }

    @Test("A document with missing or unknown values still loads instead of resetting Robi")
    func decodesLeniently() throws {
        let json = #"{"isEnabled":true,"answerModel":"someFutureModel","excludedBundleIdentifiers":["com.example.app"]}"#
        let settings = try JSONDecoder().decode(RobiSettings.self, from: Data(json.utf8))
        #expect(settings.isEnabled)
        #expect(settings.answerModel == .onDevice)
        #expect(settings.shortcutEnabled)
        #expect(settings.excludedBundleIdentifiers == ["com.example.app"])
    }

    @Test("Settings round-trip through JSON")
    func roundTrips() throws {
        var settings = RobiSettings()
        settings.isEnabled = true
        settings.answerModel = .claude
        settings.claudeEffort = .high
        settings.shortcutEnabled = false
        let decoded = try JSONDecoder().decode(RobiSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test("The store keeps the API key out of UserDefaults and reports whether one is saved")
    @MainActor
    func keepsKeyOutOfDefaults() throws {
        let suite = "robi.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = RobiMemoryKeyStore()
        let store = RobiStore(defaults: defaults, keychain: keychain)
        #expect(!store.hasClaudeKey)
        #expect(store.saveClaudeKey("  sk-ant-test  "))
        #expect(store.hasClaudeKey)
        #expect(keychain.read() == "sk-ant-test")
        store.settings.isEnabled = true
        let stored = try #require(defaults.data(forKey: "robi.settings.v1"))
        #expect(!String(decoding: stored, as: UTF8.self).contains("sk-ant"))
        store.removeClaudeKey()
        #expect(!store.hasClaudeKey)
    }

    @Test("Tab positions default to none, survive a missing or malformed value, and round-trip")
    func decodesTabPositions() throws {
        let missing = try JSONDecoder().decode(RobiSettings.self, from: Data(#"{"isEnabled":true}"#.utf8))
        #expect(missing.tabPositions.isEmpty)
        #expect(missing.isEnabled)
        let malformed = try JSONDecoder().decode(RobiSettings.self, from: Data(#"{"isEnabled":true,"tabPositions":[0.2]}"#.utf8))
        #expect(malformed.tabPositions.isEmpty)
        #expect(malformed.isEnabled)
        var settings = RobiSettings()
        settings.tabPositions = ["com.example.app": 0.25]
        let decoded = try JSONDecoder().decode(RobiSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.tabPositions == ["com.example.app": 0.25])
    }

    @Test("Saving a dropped tab persists it without reapplying settings; resetting does reapply")
    @MainActor
    func savesTabPositionQuietly() throws {
        let suite = "robi.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RobiStore(defaults: defaults, keychain: RobiMemoryKeyStore())
        var applied = 0
        store.changed = { applied += 1 }
        store.setTabPosition(0.8, for: "com.example.app")
        #expect(applied == 0)
        #expect(RobiStore(defaults: defaults, keychain: RobiMemoryKeyStore()).settings.tabPositions == ["com.example.app": 0.8])
        store.settings.tabPositions = [:]
        #expect(applied == 1)
    }
}
