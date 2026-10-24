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
}
