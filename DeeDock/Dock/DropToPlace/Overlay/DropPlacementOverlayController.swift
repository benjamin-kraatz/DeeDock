import AppKit
import SwiftUI

/// Click-through, non-activating panels, one per display, that draw the Drop to Place overlay.
///
/// The panels sit one level below the docks (`.floating`), above ordinary windows, ignore the
/// mouse, never become key, and are not drag destinations, so they cannot take focus or
/// intercept the native drag. They are ordered out whenever the model is empty and rebuilt
/// from `NSScreen.screens` at each drag start, so a display change between drags is picked up.
@MainActor
final class DropPlacementOverlayController {
    let model = DropPlacementOverlayModel()
    /// One panel per display frame, in AppKit global coordinates.
    private var panels: [(frame: CGRect, panel: NSPanel)] = []

    /// Matches the panels to the current displays. Call when a drag starts.
    func prepare() {
        let frames = NSScreen.screens.map(\.frame)
        for entry in panels where !frames.contains(entry.frame) { discard(entry.panel) }
        panels.removeAll { !frames.contains($0.frame) }
        for frame in frames where !panels.contains(where: { $0.frame == frame }) {
            panels.append((frame, makePanel(frame)))
        }
    }

    /// Shows the panels while the model has content, and orders them out once it is empty.
    func refresh() {
        if model.isEmpty {
            panels.forEach { $0.panel.orderOut(nil) }
        } else {
            panels.forEach { if !$0.panel.isVisible { $0.panel.orderFrontRegardless() } }
        }
    }

    func stop() {
        model.ghost = nil; model.outline = nil; model.pads = []
        panels.forEach { discard($0.panel) }
        panels.removeAll()
    }

    private func discard(_ panel: NSPanel) {
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
    }

    private func makePanel(_ frame: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // Above app windows, below the docks (which use `.floating`), like the approach indicator.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: DropPlacementOverlayView(model: model, screenFrame: frame))
        hosting.sizingOptions = []
        hosting.setAccessibilityElement(false)
        panel.contentView = hosting
        panel.setFrame(frame, display: false)
        return panel
    }
}
