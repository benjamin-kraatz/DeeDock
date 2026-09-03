import AppKit
import SwiftUI

/// Owns a Settings-only, click-through display marker. Constructing it creates no windows or observers.
@MainActor
final class DisplaySelectionIndicatorController {
    private var panel: IndicatorPanel?
    private var shownDisplay: DisplaySnapshot?

    /// Uses connected desktop surfaces, including displays whose DeeDock is disabled. Mirrored
    /// followers and remembered disconnected profiles are never treated as separate destinations.
    func update(selectedID: String?, displays: [DisplaySnapshot], settingsActive: Bool) {
        let desktops = displays.filter(\.hostsDock)
        guard settingsActive, desktops.count > 1, let selectedID,
              let display = desktops.first(where: { $0.id == selectedID }),
              display.frame.width > 0, display.frame.height > 0 else {
            stop()
            return
        }
        guard display != shownDisplay else { return }
        let window = panel ?? makePanel()
        panel = window
        shownDisplay = display
        // AppKit screen coordinates already use points and include negative screen origins.
        // SwiftUI's top-origin badge position is converted relative to this display's full frame.
        let reservedTop = max(0, display.frame.maxY - display.visibleFrame.maxY)
        let inset = min(reservedTop + 20, max(20, display.frame.height - 120))
        window.setFrame(display.frame, display: false)
        window.contentView = NSHostingView(rootView:
            DisplaySelectionIndicatorView(displayName: display.name, badgeTopInset: inset)
                .frame(width: display.frame.width, height: display.frame.height))
        window.orderFrontRegardless()
    }

    /// Closes the marker when Settings loses activity, selection no longer qualifies, or the app quits.
    func stop() {
        panel?.close()
        panel = nil
        shownDisplay = nil
    }

    private func makePanel() -> IndicatorPanel {
        let panel = IndicatorPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.setAccessibilityElement(false)
        return panel
    }

    /// Showing the marker must never take keyboard or main-window status away from Settings.
    private final class IndicatorPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
}
