import AppKit
import SwiftUI

private final class DockModePickerPanel: NSPanel {
    var keyboardHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if keyboardHandler?(event) != true { super.keyDown(with: event) }
    }
}

private final class DockModePickerHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class DockModePickerPanelController {
    let state: DockModePickerState
    private let panel: DockModePickerPanel
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var stopped = false
    var closed: ((Bool) -> Void)?

    init(modes: [DockMode], activeModeID: UUID, anchor: DockModePickerAnchor) {
        state = DockModePickerState(modes: modes, activeModeID: activeModeID)
        panel = DockModePickerPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.contentView = DockModePickerHostingView(rootView: DockModePickerView(state: state))
        panel.keyboardHandler = { [weak self] in self?.handleKey($0) ?? false }
        panel.setFrame(DockModePickerGeometry.frame(anchor: anchor, modeCount: modes.count), display: false)
    }

    func show() {
        installMonitors()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
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

    func close(returnFocus: Bool) {
        guard !stopped else { return }
        stopped = true
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        state.choose = nil
        panel.keyboardHandler = nil
        let callback = closed
        closed = nil
        panel.orderOut(nil)
        panel.contentView = nil
        callback?(returnFocus)
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, event.window !== panel else { return event }
            close(returnFocus: false)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in self?.close(returnFocus: false) }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76: state.chooseSelection()
        case 53: close(returnFocus: true)
        case 125: state.select(by: 1)
        case 126: state.select(by: -1)
        default: return false
        }
        return true
    }
}
