import AppKit
import SwiftUI

/// Owns Atmosphere independently of dock visibility, Dock Modes, bubbles, and Sims.
/// All geometry uses AppKit points; only window-list bounds cross from Quartz coordinates.
@MainActor
final class AtmosphereController {
    let store = AtmosphereStore()
    private struct Desktop {
        let scene: AtmosphereScene
        let ambient: NSPanel
        var decor: [NSPanel]
    }
    private var desktops: [String: Desktop] = [:]
    private var displays: [DisplaySnapshot] = []
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var paletteTask: Task<Void, Never>?
    private var suspended = false
    private var lastWallpaperRead = Date.distantPast
    private var lastSource: AtmosphereColorSource?
    private var lastWallpaperMode: AtmosphereWallpaperMode?
    private var lastPanorama: Bool?
    private var appPalette = AtmospherePalette.default

    func start() {
        guard observers.isEmpty else { return }
        store.changed = { [weak self] in self?.refresh() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspended = true; self?.refresh() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspended = false; self?.refresh() }
            })
        }
        for name in [NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.store.settings.enabled, self.store.settings.source == .appIcon else { return }
                self.readAppPalette()
                self.applyPalettes()
                self.updateGates()
            }
        })
        refresh()
    }

    func update(displays: [DisplaySnapshot]) {
        guard displays != self.displays else { return }
        self.displays = displays
        closePanels()
        lastWallpaperRead = .distantPast
        paletteTask?.cancel(); paletteTask = nil
        refresh()
    }

    private func refresh() {
        let settings = store.settings
        guard settings.enabled, !suspended else {
            timer?.invalidate(); timer = nil
            paletteTask?.cancel(); paletteTask = nil
            closePanels(); lastSource = nil
            return
        }
        if timer == nil {
            // Idle time and windows from other processes have no single permission-free notification.
            // This low-frequency gate exists only while enabled and awake; pixels never use this timer.
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateGates(); self?.readWallpaperIfNeeded() }
            }
            timer?.tolerance = 0.5
        }
        let drawable = displays.filter(\.hostsDock).sorted { $0.frame.minX < $1.frame.minX }
        let panorama = settings.panorama && AtmosphereDisplayLayout.isContinuousRow(drawable)
        let firstX = drawable.first?.frame.minX ?? 0
        let totalWidth = (drawable.last?.frame.maxX ?? firstX) - firstX
        for (index, display) in drawable.enumerated() {
            var desktop: Desktop
            if let existing = desktops[display.id] { desktop = existing }
            else {
                let scene = AtmosphereScene()
                let panel = makePanel(frame: display.frame, interactive: false)
                panel.contentView = NSHostingView(rootView: AtmosphereAmbientView(scene: scene))
                desktop = Desktop(scene: scene, ambient: panel, decor: [])
            }
            let scene = desktop.scene
            let left = !panorama || index == 0
            let right = !panorama || index == drawable.count - 1
            let decorCount = settings.preset.hasDecor ? (left ? 1 : 0) + (right ? 1 : 0) : 0
            if desktop.decor.count != decorCount || scene.leftEdge != left || scene.rightEdge != right {
                desktop.decor.forEach { $0.close() }
                desktop.decor = []
                if settings.preset.hasDecor {
                    for x in [left ? display.frame.minX : nil, right ? display.frame.maxX - 84 : nil].compactMap({ $0 }) {
                        let panel = makePanel(frame: CGRect(x: x, y: display.frame.minY, width: 84, height: 84), interactive: true)
                        panel.contentView = NSHostingView(rootView: AtmosphereDecorView(scene: scene))
                        desktop.decor.append(panel)
                    }
                }
            }
            scene.customDecor = store.decorImage
            scene.settings = settings
            scene.leftEdge = left; scene.rightEdge = right
            scene.canvasWidth = panorama ? totalWidth : display.frame.width
            scene.offset = panorama ? display.frame.minX - firstX : 0
            scene.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            scene.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            desktops[display.id] = desktop
        }
        if lastSource != settings.source || lastWallpaperMode != settings.wallpaper || lastPanorama != settings.panorama {
            paletteTask?.cancel(); paletteTask = nil
            lastWallpaperRead = .distantPast
            if settings.source == .appIcon { readAppPalette() }
        }
        lastPanorama = settings.panorama
        lastSource = settings.source
        lastWallpaperMode = settings.wallpaper
        applyPalettes()
        readWallpaperIfNeeded()
        updateGates()
    }

    private func readAppPalette() {
        appPalette = AtmospherePaletteSampler.icon(NSWorkspace.shared.frontmostApplication?.icon) ?? store.settings.manual
    }

    private func applyPalettes() {
        let palette: AtmospherePalette
        switch store.settings.source {
        case .manual: palette = store.settings.manual
        case .mood: palette = store.settings.moodPalette
        case .appIcon: palette = appPalette
        case .wallpaper: return
        }
        for desktop in desktops.values { blend(palette, into: desktop.scene) }
    }

    private func blend(_ palette: AtmospherePalette, into scene: AtmosphereScene) {
        guard palette != scene.palette else { return }
        withAnimation(scene.reduceMotion ? nil : .easeInOut(duration: 3)) { scene.palette = palette }
    }

    private func readWallpaperIfNeeded() {
        guard store.settings.source == .wallpaper, paletteTask == nil,
              Date().timeIntervalSince(lastWallpaperRead) >= 8 else { return }
        lastWallpaperRead = Date()
        let mode = store.settings.wallpaper
        let drawable = displays.filter(\.hostsDock).sorted { $0.frame.minX < $1.frame.minX }
        let panorama = store.settings.panorama && AtmosphereDisplayLayout.isContinuousRow(drawable)
        let inputs = drawable.map { display -> (String, URL?) in
            let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.runtimeID })
            return (display.id, screen.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) })
        }
        let fallback = store.settings.manual
        paletteTask = Task { [weak self] in
            var palettes: [(String, AtmospherePalette)] = []
            for (id, url) in inputs {
                let palette: AtmospherePalette?
                if let url { palette = await AtmospherePaletteSampler.wallpaper(url, mode: mode) }
                else { palette = nil }
                guard !Task.isCancelled else { return }
                palettes.append((id, palette ?? fallback))
            }
            guard let self, !Task.isCancelled else { return }
            if panorama, let first = palettes.first?.1, let last = palettes.last?.1 {
                // One palette spans the same canvas on every screen, avoiding color seams.
                let shared: AtmospherePalette
                if mode == .average {
                    let colors = palettes.map { $0.1.first }
                    let count = Double(colors.count)
                    let average = AtmosphereColor(colors.reduce(0) { $0 + $1.red } / count,
                                                  colors.reduce(0) { $0 + $1.green } / count,
                                                  colors.reduce(0) { $0 + $1.blue } / count)
                    shared = AtmospherePalette(first: average, second: average)
                } else {
                    shared = AtmospherePalette(first: first.first, second: last.second)
                }
                for desktop in self.desktops.values { self.blend(shared, into: desktop.scene) }
            } else {
                for (id, palette) in palettes {
                    if let scene = self.desktops[id]?.scene { self.blend(palette, into: scene) }
                }
            }
            self.paletteTask = nil
        }
    }

    private func updateGates() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let primaryTop = displays.first(where: \.isPrimary)?.frame.maxY ?? NSScreen.screens.first?.frame.maxY ?? 0
        for display in displays {
            guard let desktop = desktops[display.id] else { continue }
            // Quartz has a top-left origin; AppKit has a bottom-left origin, including negative screens.
            let quartz = AtmosphereDisplayLayout.quartzFrame(display.frame, primaryTop: primaryTop)
            let covered = windows.contains { info in
                guard (info[kCGWindowOwnerPID as String] as? Int32) != ProcessInfo.processInfo.processIdentifier,
                      (info[kCGWindowLayer as String] as? Int) == 0,
                      let bounds = info[kCGWindowBounds as String] as? [String: Any],
                      let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
                return frame.insetBy(dx: -1, dy: -1).contains(quartz)
            }
            let paused = covered || (store.settings.idleOnly && idle < 30)
            desktop.scene.paused = paused
            // Full-display windows are conservatively treated as fullscreen, even borderless apps.
            // Order out releases pointer interception as well as visual coverage.
            if covered {
                desktop.ambient.orderOut(nil); desktop.decor.forEach { $0.orderOut(nil) }
            } else {
                desktop.ambient.orderFrontRegardless()
                desktop.decor.forEach { $0.orderFrontRegardless() }
            }
        }
    }

    private func makePanel(frame: CGRect, interactive: Bool) -> NSPanel {
        let panel = AtmospherePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = !interactive
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.isExcludedFromWindowsMenu = true
        return panel
    }

    private func closePanels() {
        for desktop in desktops.values {
            desktop.ambient.contentView = nil; desktop.ambient.close()
            desktop.decor.forEach { $0.contentView = nil; $0.close() }
        }
        desktops.removeAll()
    }

    func stop() {
        store.changed = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        timer?.invalidate(); timer = nil
        paletteTask?.cancel(); paletteTask = nil
        closePanels()
    }
}

private final class AtmospherePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
