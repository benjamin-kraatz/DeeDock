import AppKit

/// Augments the system pointer across applications using a click-through, process-owned panel.
/// It never hides the system cursor, so a crash cannot strand a global cursor hide count.
@MainActor
final class QuarantineCursorOverlay {
    private let panel: NSPanel
    private let imageView = NSImageView()
    private let forbiddenBadge = NSImageView()
    private let targets = NSHashTable<NSView>.weakObjects()

    func register(_ target: NSView) { targets.add(target); move() }
    func unregister(_ target: NSView) { targets.remove(target); move() }

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        imageView.frame = content.bounds
        imageView.autoresizingMask = [.width, .height]
        content.addSubview(imageView)
        forbiddenBadge.frame = NSRect(x: 43, y: 1, width: 20, height: 20)
        forbiddenBadge.image = NSImage(systemSymbolName: "nosign", accessibilityDescription: nil)
        forbiddenBadge.contentTintColor = .systemRed
        forbiddenBadge.imageScaling = .scaleProportionallyUpOrDown
        forbiddenBadge.wantsLayer = true
        forbiddenBadge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.94).cgColor
        forbiddenBadge.layer?.cornerRadius = 10
        content.addSubview(forbiddenBadge)
        content.setAccessibilityElement(false)
        panel.contentView = content
    }

    func show(frame: String) {
        imageView.image = NSImage(named: frame)
        move()
        panel.orderFrontRegardless()
    }

    func move() {
        let point = NSEvent.mouseLocation
        // AppKit screen coordinates are bottom-left; artwork pad center is 32, 51 from
        // the top-left of the 64-point canvas. Preserve that anchor across both frames.
        panel.setFrameOrigin(NSPoint(x: point.x - 32, y: point.y - 13))
        let allowed = canStamp(at: point)
        forbiddenBadge.isHidden = allowed
        imageView.alphaValue = allowed ? 1 : 0.65
    }

    private func canStamp(at point: NSPoint) -> Bool {
        // Ignore our click-through cursor panel, but never accept a target obscured by
        // another app or a menu. All coordinates here are AppKit points, including negatives.
        var number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: panel.windowNumber)
        while let window = NSApp.window(withWindowNumber: number), window.ignoresMouseEvents {
            let next = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: number)
            guard next != number else { return false }
            number = next
        }
        return targets.allObjects.contains { view in
            guard let window = view.window, window.windowNumber == number, window.isVisible,
                  !view.isHiddenOrHasHiddenAncestor else { return false }
            let local = view.convert(window.convertPoint(fromScreen: point), from: nil)
            return view.visibleRect.contains(local)
        }
    }

    func close() { panel.close() }
}
