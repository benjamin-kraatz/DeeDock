import AppKit
import SwiftUI

private final class CourtPanel: NSPanel {
    var key: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if key?(event) != true { super.keyDown(with: event) }
    }
}

/// Floating UI only. Event monitors exist solely while the stage is visible.
@MainActor final class CourtPanelController: NSObject, NSWindowDelegate {
    private let panel: CourtPanel
    private weak var hearing: CourtHearing?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screensObserver: NSObjectProtocol?
    private var regions: [CGRect] = []
    private var restoring = true
    private let frameKey = "court.stage.frame"

    init(hearing: CourtHearing, origin: CGPoint) {
        self.hearing = hearing
        panel = CourtPanel(contentRect: CGRect(x: origin.x - 350, y: origin.y + 30, width: 700, height: 550),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = String(localized: .courtTitle)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .ignoresCycle]
        panel.delegate = self
        let view = CourtStageView(hearing: hearing) { [weak self] regions in
            self?.regions = regions; self?.updateHitTesting()
        }
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentView = hosting
        if !hearing.sample, let raw = UserDefaults.standard.string(forKey: frameKey) {
            let saved = NSRectFromString(raw)
            if saved.width.isFinite, saved.origin.x.isFinite, saved.origin.y.isFinite { panel.setFrameOrigin(saved.origin) }
        }
        repairPlacement()
        restoring = false
        hearing.beginDrag = { [weak self] event in self?.panel.performDrag(with: event) }
        hearing.move = { [weak self] x, y in self?.move(x, y) }
        panel.key = { [weak self, weak hearing] event in
            if event.keyCode == 53 { hearing?.close?(); return true }
            if event.modifierFlags.contains(.option) {
                switch event.keyCode {
                case 123: self?.move(-24, 0)
                case 124: self?.move(24, 0)
                case 125: self?.move(0, -24)
                case 126: self?.move(0, 24)
                default: return false
                }
                return true
            }
            return false
        }
    }

    func show() {
        panel.orderFrontRegardless()
        if hearing?.sample == true { panel.makeKeyAndOrderFront(nil) }
        // Returning nil from hitTest does not pass clicks to another process. Toggle the
        // window's event eligibility using actual SwiftUI island bounds before mouse-down.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in self?.updateHitTesting() }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in self?.updateHitTesting(); return event }
        screensObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.repairPlacement() } }
        updateHitTesting()
    }

    private func updateHitTesting() {
        let mouse = NSEvent.mouseLocation
        // SwiftUI's named space has a top-left origin; AppKit screen coordinates are bottom-left points.
        let local = CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)
        panel.ignoresMouseEvents = !regions.contains { NSBezierPath(roundedRect: $0, xRadius: 20, yRadius: 20).contains(local) }
    }

    private func move(_ x: CGFloat, _ y: CGFloat) {
        panel.setFrameOrigin(CGPoint(x: panel.frame.minX + x, y: panel.frame.minY + y))
        repairPlacement(); save()
    }

    private func repairPlacement() {
        guard let screen = NSScreen.screens.max(by: {
            $0.visibleFrame.intersection(panel.frame).width * $0.visibleFrame.intersection(panel.frame).height <
            $1.visibleFrame.intersection(panel.frame).width * $1.visibleFrame.intersection(panel.frame).height
        }) else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: max(frame.minX, min(panel.frame.minX, frame.maxX - panel.frame.width)),
                                     y: max(frame.minY, min(panel.frame.minY, frame.maxY - panel.frame.height))))
        updateHitTesting()
    }

    func windowDidMove(_ notification: Notification) { save(); updateHitTesting() }
    func windowDidResize(_ notification: Notification) { repairPlacement() }
    private func save() {
        if !restoring, hearing?.sample == false { UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: frameKey) }
    }
    func close() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let screensObserver { NotificationCenter.default.removeObserver(screensObserver) }
        localMonitor = nil; globalMonitor = nil; screensObserver = nil
        panel.orderOut(nil); panel.close()
    }
}
