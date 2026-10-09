import CoreGraphics
import Foundation
import Testing
@testable import DeeDock

@MainActor struct HubGeometryTests {
    private let margin = HubStyle.screenMargin
    private let reach = HubStyle.anchorGap + HubStyle.pointerSize.height

    @Test("A roomy display gets the ideal size, centered over the tile with the pointer on its center")
    func idealPlacement() {
        let visible = CGRect(x: 0, y: 80, width: 2560, height: 1360)
        let tile = CGRect(x: 1200, y: 20, width: 56, height: 56)
        let placement = HubGeometry.anchoredPlacement(anchor: HubAnchor(tile: tile, edge: .bottom, visibleFrame: visible))
        #expect(placement.body.size == HubStyle.anchoredSize)
        #expect(placement.body.midX == tile.midX)
        #expect(placement.pointerOffset == tile.midX - placement.body.minX)
        // The tile sits below the visible frame's bottom (inside the system Dock's reserved strip),
        // so the body starts at the inset visible frame, not at the pointer's reach.
        #expect(placement.body.minY == max(tile.maxY + reach, visible.minY + margin))
    }

    @Test("The pointer tip sits anchorGap above the tile when the visible frame allows it")
    func pointerTipGap() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let tile = CGRect(x: 600, y: 40, width: 48, height: 48)
        let placement = HubGeometry.anchoredPlacement(anchor: HubAnchor(tile: tile, edge: .bottom, visibleFrame: visible))
        let tip = HubGeometry.pointerTip(of: placement)
        #expect(tip.y == tile.maxY + HubStyle.anchorGap)
        #expect(tip.x == tile.midX)
    }

    @Test("A small display clamps the body inside the visible frame minus the margin")
    func smallDisplayClamp() {
        let visible = CGRect(x: 0, y: 0, width: 1024, height: 600)
        let tile = CGRect(x: 30, y: 10, width: 48, height: 48)
        let placement = HubGeometry.anchoredPlacement(anchor: HubAnchor(tile: tile, edge: .bottom, visibleFrame: visible))
        let available = visible.insetBy(dx: margin, dy: margin)
        #expect(available.contains(placement.body))
        #expect(placement.body.width == available.width)
        #expect(placement.body.height == available.maxY - (tile.maxY + reach))
        #expect(placement.body.minY == tile.maxY + reach)
    }

    @Test("Pointer x follows the tile under clamping and stays clear of the rounded corners")
    func pointerUnderClamp() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Near the left end: the body clamps to the margin, so the pointer moves toward its left edge.
        let left = CGRect(x: 60, y: 8, width: 48, height: 48)
        let placement = HubGeometry.anchoredPlacement(anchor: HubAnchor(tile: left, edge: .bottom, visibleFrame: visible))
        #expect(placement.body.minX == visible.minX + margin)
        #expect(placement.body.minX + placement.pointerOffset == left.midX)
        // Past the far corner: the pointer stops at the corner inset instead of leaving the body.
        let corner = CGRect(x: -10, y: 8, width: 20, height: 20)
        let clamped = HubGeometry.anchoredPlacement(anchor: HubAnchor(tile: corner, edge: .bottom, visibleFrame: visible))
        #expect(clamped.pointerOffset == HubGeometry.pointerInset)
        let right = CGRect(x: 1420, y: 8, width: 48, height: 48)
        let farRight = HubGeometry.anchoredPlacement(anchor: HubAnchor(tile: right, edge: .bottom, visibleFrame: visible))
        #expect(farRight.body.maxX == visible.maxX - margin)
        #expect(farRight.pointerOffset == farRight.body.width - HubGeometry.pointerInset)
    }

    @Test("A display left of and below the primary one (negative origin) places the Hub on that display")
    func negativeOrigin() {
        let visible = CGRect(x: -1920, y: -1080, width: 1920, height: 1055)
        let tile = CGRect(x: -1000, y: -1072, width: 52, height: 52)
        let placement = HubGeometry.anchoredPlacement(anchor: HubAnchor(tile: tile, edge: .bottom, visibleFrame: visible))
        #expect(visible.insetBy(dx: margin, dy: margin).contains(placement.body))
        #expect(placement.body.minX + placement.pointerOffset == tile.midX)
        #expect(placement.body.minY == tile.maxY + reach)
    }

    @Test("A left dock opens the Hub to the right of the tile, pointing back along y")
    func leftDock() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let tile = CGRect(x: 8, y: 500, width: 52, height: 52)
        let placement = HubGeometry.anchoredPlacement(anchor: HubAnchor(tile: tile, edge: .left, visibleFrame: visible))
        #expect(placement.edge == .left)
        #expect(placement.body.minX == tile.maxX + reach)
        #expect(placement.body.maxX <= visible.maxX - margin)
        // Measured from the body's top edge in a y-down space.
        #expect(placement.body.maxY - placement.pointerOffset == tile.midY)
        let tip = HubGeometry.pointerTip(of: placement)
        #expect(tip.x == tile.maxX + HubStyle.anchorGap)
    }

    @Test("A right dock opens the Hub to the left of the tile and clamps near the top")
    func rightDock() {
        let visible = CGRect(x: 1920, y: 0, width: 1280, height: 800)
        let tile = CGRect(x: 3140, y: 740, width: 48, height: 48)
        let placement = HubGeometry.anchoredPlacement(anchor: HubAnchor(tile: tile, edge: .right, visibleFrame: visible))
        let available = visible.insetBy(dx: margin, dy: margin)
        #expect(placement.body.maxX == tile.minX - reach)
        #expect(available.contains(placement.body))
        #expect(placement.body.maxY == available.maxY)
        #expect(placement.pointerOffset >= HubGeometry.pointerInset)
    }

    @Test("A remembered detached frame on an unplugged display recenters on the fallback")
    func restoredFrameOffscreen() {
        let fallback = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let gone = CGRect(x: 4000, y: 200, width: 1000, height: 600)
        let frame = HubGeometry.restoredDetachedFrame(gone, visibleFrames: [fallback], fallback: fallback)
        #expect(fallback.contains(frame))
        #expect(frame.midX == fallback.midX && frame.midY == fallback.midY)
        #expect(frame.size == gone.size)
    }

    @Test("A remembered detached frame is kept at least the minimum size and inside its display")
    func restoredFrameClamped() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 875), CGRect(x: -1280, y: 0, width: 1280, height: 775)]
        let saved = CGRect(x: -1300, y: 100, width: 400, height: 300)
        let frame = HubGeometry.restoredDetachedFrame(saved, visibleFrames: screens, fallback: screens[0])
        #expect(screens[1].contains(frame))
        #expect(frame.width == HubStyle.minimumDetachedSize.width && frame.height == HubStyle.minimumDetachedSize.height)
    }

    @Test("Hub preferences survive a round trip and fall back to defaults when unreadable")
    func preferencesRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "HubGeometryTests.\(UUID().uuidString)"))
        #expect(HubShellPreferences.load(from: defaults) == HubShellPreferences())
        var preferences = HubShellPreferences()
        preferences.lastTab = .files
        preferences.detached = true
        preferences.detachedFrame = CGRect(x: -900, y: 40, width: 1000, height: 620)
        preferences.save(to: defaults)
        #expect(HubShellPreferences.load(from: defaults) == preferences)
        defaults.set(Data("{\"lastTab\":\"radar\"}".utf8), forKey: HubShellPreferences.defaultsKey)
        #expect(HubShellPreferences.load(from: defaults).lastTab == .apps)
    }

    @Test("Dock settings saved with the retired launcher style still decode")
    func retiredLauncherStyle() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(DockSettings.defaults)) as? [String: Any])
        object["launcherStyle"] = "compact"
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(DockSettings.self, from: legacy)
        #expect(decoded.iconSize == DockSettings.defaults.iconSize)
        #expect(decoded.launcherLineIcons == DockSettings.defaults.launcherLineIcons)
        let overrides = try JSONDecoder().decode(DockSettingsOverrides.self, from: Data("{\"launcherStyle\":\"full\",\"iconSize\":40}".utf8))
        #expect(overrides.iconSize == 40)
    }
}
