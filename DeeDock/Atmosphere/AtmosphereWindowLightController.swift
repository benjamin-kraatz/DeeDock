import AppKit
import SwiftUI

/// Owns one nonactivating halo, AX subscriptions, and at most one in-flight color sample.
@MainActor
final class AtmosphereWindowLightController {
    private let tracker = AtmosphereFocusedWindowTracker()
    private let capture = AtmosphereWindowLightCapture()
    private let scene = AtmosphereWindowLightScene()
    private var panel: NSPanel?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var target: AtmosphereFocusedWindowTracker.Target?
    private var settings = AtmosphereSettings()
    private var displays: [DisplaySnapshot] = []
    private var lastSample = Date.distantPast
    private var randomColors = AtmosphereWindowLightPalette.dzwei
    private var lastRandom = Date.distantPast

    /// Called by Atmosphere's existing lifecycle and two-second permission/idle reconciliation.
    func update(settings: AtmosphereSettings, displays: [DisplaySnapshot]) {
        if self.settings.ambientLight.mode != settings.ambientLight.mode {
            cancelSample()
            lastSample = .distantPast
            scene.colors = AtmosphereWindowLightPalette.dzwei
        }
        self.settings = settings
        self.displays = displays
        guard settings.enabled, settings.ambientLight.enabled else { stop(); return }
        tracker.changed = { [weak self] in self?.refresh() }
        scene.settings = settings.ambientLight
        scene.intensity = AtmosphereLimits.clamped(settings.intensity)
        scene.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        scene.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        refresh()
    }

    private func refresh() {
        guard settings.enabled, settings.ambientLight.enabled else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        guard !settings.idleOnly || idle >= 30, let next = tracker.target() else { hide(); return }
        let primaryTop = displays.first(where: \.isPrimary)?.frame.maxY ?? NSScreen.screens.first?.frame.maxY ?? 0
        // AX/Quartz top-left points -> AppKit bottom-left points, including displays with negative origins.
        let frame = CGRect(x: next.frame.minX, y: primaryTop - next.frame.maxY,
                           width: next.frame.width, height: next.frame.height)
        let drawable = displays.filter { $0.hostsDock && $0.frame.intersects(frame) }
        guard !drawable.isEmpty,
              !drawable.contains(where: { frame.insetBy(dx: -1, dy: -1).contains($0.frame) }) else { hide(); return }
        if target?.id != next.id || target?.pid != next.pid {
            cancelSample()
            lastSample = .distantPast
            lastRandom = .distantPast
            scene.colors = AtmosphereWindowLightPalette.dzwei
        }
        target = next
        if panel == nil {
            let created = AtmosphereWindowLightPanel(contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            created.isReleasedWhenClosed = false
            created.backgroundColor = .clear
            created.isOpaque = false
            created.hasShadow = false
            created.ignoresMouseEvents = true
            created.hidesOnDeactivate = false
            created.level = .normal
            created.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            created.isExcludedFromWindowsMenu = true
            created.contentView = NSHostingView(rootView: AtmosphereWindowLightView(scene: scene))
            panel = created
        }
        panel?.setFrame(frame.insetBy(dx: -AtmosphereWindowLightView.margin, dy: -AtmosphereWindowLightView.margin), display: true)
        // Keep the halo behind its source, so it cannot tint that window or cover menus above it.
        panel?.order(.below, relativeTo: Int(next.id))
        scene.visible = true
        updateColors(for: next)
    }

    private func updateColors(for target: AtmosphereFocusedWindowTracker.Target) {
        let mode = settings.ambientLight.mode
        switch mode {
        case .dzwei: blend(AtmosphereWindowLightPalette.dzwei)
        case .daylight: blend(AtmosphereWindowLightPalette.daylight(at: Date()))
        case .random:
            if Date().timeIntervalSince(lastRandom) >= 30 {
                lastRandom = Date()
                let color = NSColor(calibratedHue: .random(in: 0...1), saturation: 0.55, brightness: 0.72, alpha: 1)
                    .usingColorSpace(.sRGB)!
                randomColors = [.init(color.redComponent, color.greenComponent, color.blueComponent)]
            }
            blend(randomColors)
        case .average, .dominant:
            guard CGPreflightScreenCaptureAccess() else {
                cancelSample()
                blend(AtmosphereWindowLightPalette.dzwei)
                return
            }
            guard task == nil, Date().timeIntervalSince(lastSample) >= 2 else { return }
            lastSample = Date()
            let request = generation
            task = Task { [weak self, capture] in
                let colors = await capture.colors(windowID: target.id, pid: target.pid, mode: mode)
                guard let self, !Task.isCancelled, request == self.generation else { return }
                self.task = nil
                guard self.target?.id == target.id, self.target?.pid == target.pid,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else { return }
                // A nil sample is busy, cancelled, or a transient ScreenCapture miss — not a
                // new palette. Applying the default here flashes DZWEI over a good halo.
                guard let colors else { return }
                self.blend(colors)
            }
        }
    }

    private func blend(_ colors: [AtmosphereColor]) {
        guard scene.colors != colors else { return }
        withAnimation(scene.reduceMotion ? nil : .easeInOut(duration: 1.5)) { scene.colors = colors }
    }

    private func cancelSample() {
        generation += 1
        task?.cancel()
        task = nil
    }

    private func hide() {
        scene.visible = false
        panel?.orderOut(nil)
        // Keep the last target so the same window does not reset to DZWEI on the next show.
        cancelSample()
    }

    /// Stop is also used during sleep, session resignation, display changes, and feature disablement.
    func stop() {
        hide()
        tracker.changed = nil
        tracker.stop()
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }
}

private final class AtmosphereWindowLightPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
