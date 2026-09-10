import AppKit
import SwiftUI

/// Click-through overlay that draws alignment guides only while a pin or stack is magnetized.
@MainActor
final class DockMagneticGuideController {
    private var panel: NSPanel?

    /// Shows `guides` in screen space, or hides the overlay when the drag is free.
    ///
    /// The panel ignores mouse events and stays below the native drag image so it cannot
    /// steal focus or intercept the drop.
    func show(_ guides: [DockMagneticGuide]) {
        guard !guides.isEmpty else {
            hide()
            return
        }
        let canvas = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        guard !canvas.isNull, canvas.width > 0, canvas.height > 0 else {
            hide()
            return
        }
        let panel = preparedPanel()
        panel.setFrame(canvas, display: true)
        let local = guides.map { $0.convertedToTopLeft(in: canvas) }
        panel.contentView = NSHostingView(
            rootView: DockMagneticGuidesView(guides: local, canvasSize: canvas.size)
                .frame(width: canvas.width, height: canvas.height)
        )
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    func stop() {
        hide()
        panel?.close()
        panel = nil
    }

    private func preparedPanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        // Sit just under the native drag image so guides never steal the icon or the pointer.
        let draggingLevel = Int(CGWindowLevelForKey(.draggingWindow))
        panel.level = NSWindow.Level(rawValue: draggingLevel - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.panel = panel
        return panel
    }
}
