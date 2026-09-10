import AppKit
import SwiftUI

/// Owns one nonactivating, click-through overlay per drawable desktop.
/// Frames use AppKit screen points, including negative origins; mirrored destinations are omitted.
@MainActor
final class Mode69AmbientController {
    private var panels: [String: NSPanel] = [:]
    private var displays: [DisplaySnapshot] = []
    private var enabled = false
    private var suspended = false
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
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
        observers.append(center.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    func update(displays: [DisplaySnapshot], enabled: Bool) {
        guard displays != self.displays || enabled != self.enabled else { return }
        self.displays = displays
        self.enabled = enabled
        refresh()
    }

    private func refresh() {
        // Releasing hosting views also removes their animation timelines during sleep or disable.
        panels.values.forEach { $0.contentView = nil; $0.close() }
        panels.removeAll()
        guard enabled, !suspended else { return }
        let workspace = NSWorkspace.shared
        for display in displays where display.hostsDock {
            let panel = Mode69AmbientPanel(contentRect: display.frame,
                                          styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isExcludedFromWindowsMenu = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: Mode69AmbientView(
                reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
                reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency))
            panel.setFrame(display.frame, display: true)
            panel.orderFrontRegardless()
            panels[display.id] = panel
        }
    }

    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        enabled = false
        refresh()
    }
}

/// Decoration must never become a keyboard or main window, including during Space changes.
private final class Mode69AmbientPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
