import AppKit
import QuartzCore

/// A temporary, click-through outline. Core Animation draws it without per-frame AX work.
@MainActor final class AppMeltReveal {
    private var panel: NSPanel?

    func show(frame: CGRect) {
        stop()
        guard let primary = NSScreen.screens.first else { return }
        let rect = AppMeltGeometry.appKit(frame, primaryTop: primary.frame.maxY).insetBy(dx: -12, dy: -12)
        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.transient, .fullScreenNone, .ignoresCycle]
        let view = NSView(frame: CGRect(origin: .zero, size: rect.size))
        view.wantsLayer = true
        view.setAccessibilityElement(false)
        panel.contentView = view
        let path = CGPath(roundedRect: view.bounds.insetBy(dx: 13, dy: 13), cornerWidth: 16, cornerHeight: 16, transform: nil)
        for isHighlight in [false, true] {
            let line = CAShapeLayer()
            line.frame = view.bounds
            line.path = path
            line.fillColor = nil
            line.strokeColor = (isHighlight ? NSColor.white : NSColor.systemCyan).cgColor
            line.lineWidth = isHighlight ? 2 : 3
            line.lineCap = .round
            line.shadowColor = NSColor.systemCyan.cgColor
            line.shadowRadius = isHighlight ? 5 : 10
            line.shadowOpacity = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 0 : 0.9
            line.shadowOffset = .zero
            view.layer?.addSublayer(line)
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0; draw.toValue = 1; draw.duration = 0.7
            draw.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            line.add(draw, forKey: "draw")
            if isHighlight {
                // A short bright tail chases the drawing edge, then disappears at completion.
                line.strokeStart = 1
                let tail = CABasicAnimation(keyPath: "strokeStart")
                tail.fromValue = 0; tail.toValue = 1; tail.duration = 0.7
                tail.beginTime = CACurrentMediaTime() + 0.08
                tail.fillMode = .backwards
                tail.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                line.add(tail, forKey: "tail")
            }
        }
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func fade() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel?.animator().alphaValue = 0
        }
    }

    func stop() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }
}
