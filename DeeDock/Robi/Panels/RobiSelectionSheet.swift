import AppKit

/// The transparent sheet laid over the window in selection mode.
///
/// It takes the drag so the app underneath never sees it: that is what lets the person select a
/// region without a modifier key or an event tap, and leaves ordinary drags in the app alone the
/// rest of the time. A click without a drag takes the whole window; Return or Space does too, and
/// Escape cancels.
final class RobiSelectionSheet {
    private let panel = RobiPanel()
    private let view = RobiSelectionView()

    /// A region in window-local top-left points.
    var regionPicked: ((CGRect) -> Void)? {
        get { view.regionPicked }
        set { view.regionPicked = newValue }
    }
    var windowPicked: (() -> Void)? {
        get { view.windowPicked }
        set { view.windowPicked = newValue }
    }
    var cancelled: (() -> Void)? {
        get { view.cancelled }
        set { view.cancelled = newValue }
    }

    init() {
        panel.allowsKey = true
        panel.contentView = view
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(String(localized: .robiSelectionAccessibility))
    }

    /// Covers the window, given in AppKit points, and takes the keyboard for Escape and Return.
    func show(over window: CGRect, below companion: NSWindow?) {
        panel.setFrame(window, display: true)
        panel.orderFrontRegardless()
        if let companion { companion.order(.above, relativeTo: panel.windowNumber) }
        panel.makeKey()
        panel.makeFirstResponder(view)
    }

    func move(over window: CGRect) {
        guard panel.isVisible else { return }
        panel.setFrame(window, display: true)
    }

    func close() {
        view.reset()
        panel.orderOut(nil)
    }
}

/// Draws the dim, the dashed selection rectangle, and handles the gestures.
private final class RobiSelectionView: NSView {
    var regionPicked: ((CGRect) -> Void)?
    var windowPicked: (() -> Void)?
    var cancelled: (() -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private var selection: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    func reset() { start = nil; current = nil; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        // Matches macOS window corners closely enough that the dim reads as part of the window.
        let window = NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16)
        NSColor.black.withAlphaComponent(0.12).setFill()
        window.fill()
        guard let rect = selection else { return }
        let outline = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSGraphicsContext.current?.compositingOperation = .copy
        NSColor.clear.setFill()
        outline.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
        outline.fill()
        NSColor.controlAccentColor.setStroke()
        outline.lineWidth = 2
        outline.setLineDash([7, 4], count: 2, phase: 0)
        outline.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let picked = selection
        reset()
        guard let picked, picked.width > 12, picked.height > 12 else { windowPicked?(); return }
        regionPicked?(CGRect(x: picked.minX, y: bounds.height - picked.maxY, width: picked.width, height: picked.height))
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: cancelled?()                // Escape
        case 36, 49, 76: windowPicked?()     // Return, Space, Enter
        default: super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        windowPicked?()
        return true
    }
}
