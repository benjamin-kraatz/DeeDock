import AppKit
import SwiftUI

/// Owns one display's approach glow: a nonactivating, click-through panel along the dock edge.
///
/// The dock panel controller feeds it every pointer sample it already receives, so the glow adds
/// no monitor or timer of its own. The panel is ordered out shortly after the glow fades, and
/// nothing is scheduled while the pointer is away from the edge.
@MainActor final class DockApproachIndicatorController {
    private let model = DockApproachGlowModel()
    private var panel: NSPanel?
    private var geometry: DockApproachGeometry?
    private var enabled = false
    private var colorMode: DockBehaviorSettings.ApproachColor = .automatic
    private var screen: NSScreen?
    /// Fade length when the dock starts revealing; follows the configured animation duration.
    private var dismissDuration: Double = 0.2
    private var orderOutTask: Task<Void, Never>?
    private var toneTask: Task<Void, Never>?
    private var lastToneSample: TimeInterval = -.infinity
    private var wallpaperLuminance: Double?

    /// Applies settings and geometry. Disabling hides the glow at once and closes the panel.
    ///
    /// - Parameters:
    ///   - enabled: The approach indicator setting combined with auto-hide; the glow never shows otherwise.
    ///   - screenFrame: The display's full frame in AppKit screen coordinates.
    ///   - zone: The activation zone in the same space.
    ///   - runtimeID: The display handle used to find its wallpaper.
    func configure(enabled: Bool, settings: DockBehaviorSettings, screenFrame: CGRect, zone: CGRect, edge: DockEdge,
                   runtimeID: UInt32, reduceMotion: Bool, reduceTransparency: Bool) {
        let updated = DockApproachGeometry(screen: screenFrame, zone: zone, edge: edge)
        let geometryChanged = geometry != updated
        let modeChanged = colorMode != settings.approachColor
        self.enabled = enabled
        colorMode = settings.approachColor
        dismissDuration = max(0.12, settings.animationDuration)
        model.reduceMotion = reduceMotion
        model.reduceTransparency = reduceTransparency
        screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == runtimeID
        }
        guard enabled else { close(); return }
        if geometryChanged {
            if let previous = geometry, previous.edge != edge { wallpaperLuminance = nil; lastToneSample = -.infinity }
            geometry = updated
            model.metrics = DockApproachGlowMetrics(updated)
            panel?.setFrame(updated.frame, display: true)
        }
        if modeChanged || geometryChanged { applyTone(animated: false) }
        if colorMode == .automatic { refreshWallpaperTone() }
    }

    /// Follows the pointer while the dock is fully hidden or waiting out its reveal delay.
    ///
    /// - Parameters:
    ///   - armed: False once the dock begins revealing, which fades the glow over the reveal.
    func update(pointer: CGPoint, armed: Bool) {
        guard enabled, let geometry else { return }
        let sample = armed ? geometry.sample(pointer: pointer) : DockApproachSample(intensity: 0, surge: 0, focus: model.focus)
        // Quantize so the global mouse stream does not restart animations for invisible changes.
        let intensity = (sample.intensity * 200).rounded() / 200
        let surge = intensity > 0 ? (sample.surge * 200).rounded() / 200 : 0
        let focusMoved = abs(sample.focus - model.focus) >= 1
        guard intensity != model.intensity || surge != model.surge || (intensity > 0 && focusMoved) else { return }
        let appearing = model.intensity == 0 && intensity > 0
        if intensity > 0 {
            orderOutTask?.cancel(); orderOutTask = nil
            showPanel()
            if appearing {
                // Start from the pointer's position rather than sliding in from the previous one.
                model.focus = sample.focus
                if colorMode == .automatic { refreshWallpaperTone() }
            }
        }
        withAnimation(animation(armed: armed)) {
            model.intensity = intensity
            model.surge = surge
            if intensity > 0 { model.focus = sample.focus }
        }
        if intensity == 0 { scheduleOrderOut(after: armed ? 0.4 : dismissDuration + 0.1) }
    }

    /// Fades out without closing, for sleep and Launcher presentation.
    func hide() { update(pointer: .zero, armed: false) }

    func stop() {
        enabled = false
        toneTask?.cancel(); toneTask = nil
        close()
    }

    private func animation(armed: Bool) -> Animation {
        // Opacity changes are not motion, so Reduce Motion keeps a short crossfade instead of a spring.
        if model.reduceMotion { return .linear(duration: 0.12) }
        return armed ? .smooth(duration: 0.28) : .easeOut(duration: dismissDuration)
    }

    private func showPanel() {
        guard let geometry else { return }
        if panel == nil {
            let panel = NSPanel(contentRect: geometry.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.ignoresMouseEvents = true; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
            // Just below the dock panel's floating level, so a revealing dock always draws over the glow.
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            panel.contentView = NSHostingView(rootView: DockApproachGlowView(model: model))
            self.panel = panel
        }
        guard let panel else { return }
        if panel.frame != geometry.frame { panel.setFrame(geometry.frame, display: false) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func scheduleOrderOut(after delay: Double) {
        guard panel?.isVisible == true, orderOutTask == nil else { return }
        orderOutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            orderOutTask = nil
            if model.intensity == 0 { panel?.orderOut(nil) }
        }
    }

    private func close() {
        orderOutTask?.cancel(); orderOutTask = nil
        model.intensity = 0; model.surge = 0
        panel?.close(); panel = nil
    }

    private func applyTone(animated: Bool) {
        let tone: DockApproachTone = switch colorMode {
        case .accent: .accent
        case .automatic:
            .automatic(luminance: wallpaperLuminance,
                       darkAppearance: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        }
        guard tone != model.tone else { return }
        withAnimation(animated && !model.reduceMotion ? .easeInOut(duration: 0.3) : nil) { model.tone = tone }
    }

    /// macOS posts no public wallpaper-change notification, so the wallpaper is re-read when an
    /// approach begins, at most every ten seconds. Decoding happens off the main actor.
    private func refreshWallpaperTone() {
        let now = ProcessInfo.processInfo.systemUptime
        guard toneTask == nil, now - lastToneSample >= 10, let geometry,
              let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
        lastToneSample = now
        let edge = geometry.edge
        toneTask = Task { [weak self] in
            let luminance = await DockApproachWallpaperSampler.luminance(of: url, near: edge)
            guard let self, !Task.isCancelled else { return }
            toneTask = nil
            guard geometry.edge == self.geometry?.edge else { return }
            if let luminance { wallpaperLuminance = luminance }
            applyTone(animated: true)
        }
    }
}
