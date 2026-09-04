import AppKit
import SwiftUI

private final class WindowPeekPanel: NSPanel {
    var acceptsKeyboardFocus = false
    var keyboardHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if keyboardHandler?(event) != true { super.keyDown(with: event) }
    }
}

private final class WindowPeekHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the native panel for one Peek presentation.
@MainActor
final class WindowPeekPanelController {
    let state: WindowPeekState
    private let panel: WindowPeekPanel
    private let keyboard: Bool
    private var placement: WindowPeekPlacement
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var stopped = false
    var closed: ((Bool) -> Void)?

    init(item: DockItem, anchor: WindowPeekAnchor, settings: DockSettings, keyboard: Bool) {
        state = WindowPeekState(item: item, settings: settings)
        self.keyboard = keyboard
        placement = WindowPeekGeometry.placement(anchor: anchor, settings: settings, count: 1)
        panel = WindowPeekPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.acceptsKeyboardFocus = keyboard
        panel.contentView = WindowPeekHostingView(rootView: WindowPeekView(state: state, keyboard: keyboard))
        panel.keyboardHandler = { [weak self] event in self?.handleKey(event) ?? false }
        panel.setFrame(placement.frame, display: false)
    }

    func show() {
        installMonitors()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        if keyboard { panel.makeKeyAndOrderFront(nil) }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    func update(anchor: WindowPeekAnchor, settings: DockSettings, count: Int) {
        state.settings = settings
        placement = WindowPeekGeometry.placement(anchor: anchor, settings: settings, count: count)
        panel.setFrame(placement.frame, display: true)
    }

    func contains(_ screenPoint: CGPoint) -> Bool { panel.frame.contains(screenPoint) }

    func close(returnFocus: Bool) {
        guard !stopped else { return }
        stopped = true
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        state.choose = nil
        state.showApp = nil
        state.settingsSelected = nil
        state.showAll = nil
        state.hovered = nil
        state.thumbnailNeeded = nil
        panel.keyboardHandler = nil
        let callback = closed
        closed = nil
        callback?(returnFocus)
        panel.orderOut(nil)
        panel.contentView = nil
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, event.window !== self.panel else { return event }
            self.close(returnFocus: false)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.close(returnFocus: false)
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76: state.chooseSelection()
        case 53: close(returnFocus: true)
        case 123, 126: state.select(by: -1)
        case 124, 125: state.select(by: 1)
        default: return false
        }
        return true
    }
}
