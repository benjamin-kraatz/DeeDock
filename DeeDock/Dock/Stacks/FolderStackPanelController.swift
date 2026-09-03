import AppKit
import SwiftUI

private final class FolderStackPanel: NSPanel {
    var acceptsKeyboardFocus = false
    var keyboardHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if keyboardHandler?(event) != true { super.keyDown(with: event) }
    }
}

private final class FolderStackHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class FolderStackPanelController {
    let state: FolderStackState
    private let panel: FolderStackPanel
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var stopped = false
    private let keyboard: Bool
    private let reduceMotion: Bool
    private var placement: FolderStackPlacement
    private var sourceIcon: CGRect
    var closed: ((Bool) -> Void)?

    init(folder: FolderReference, anchor: FolderStackAnchor, keyboard: Bool) {
        state = FolderStackState(folder: folder)
        self.keyboard = keyboard
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        placement = FolderStackGeometry.placement(anchor: anchor)
        sourceIcon = anchor.icon
        panel = FolderStackPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.acceptsKeyboardFocus = keyboard
        state.chrome = placement.chrome
        panel.contentView = FolderStackHostingView(rootView: FolderStackView(state: state, keyboard: keyboard))
        panel.keyboardHandler = { [weak self] in self?.handleKey($0) ?? false }
        panel.setFrame(placement.frame, display: false)
    }

    func show() {
        installMonitors()
        if reduceMotion {
            panel.alphaValue = 1
            panel.setFrame(placement.frame, display: true)
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.setFrame(FolderStackGeometry.dismissedFrame(from: placement.frame, edge: placement.chrome.edge), display: false)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(placement.frame, display: true)
            }
        }
        if keyboard {
            state.selectedID = state.entries.first?.id
            panel.makeKeyAndOrderFront(nil)
        }
        state.start()
    }

    func update(_ anchor: FolderStackAnchor) {
        placement = FolderStackGeometry.placement(anchor: anchor)
        sourceIcon = anchor.icon
        state.chrome = placement.chrome
        panel.setFrame(placement.frame, display: true)
    }

    func open(_ entry: FolderStackEntryReference) {
        guard FileManager.default.fileExists(atPath: entry.url.path) else {
            state.report(String(localized: .folderStackItemUnavailable(itemName: entry.name))) { [weak self] in self?.open(entry) }
            return
        }
        if entry.isFolder {
            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            close(returnFocus: false)
        } else if NSWorkspace.shared.open(entry.url) {
            close(returnFocus: false)
        } else {
            state.report(String(localized: .folderStackOpenFailed(itemName: entry.name))) { [weak self] in self?.open(entry) }
        }
    }

    func close(returnFocus: Bool) {
        guard !stopped else { return }
        stopped = true
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil; globalMonitor = nil
        state.stop()
        panel.keyboardHandler = nil
        let callback = closed
        closed = nil
        callback?(returnFocus)
        guard !reduceMotion, panel.isVisible else {
            panel.orderOut(nil)
            panel.contentView = nil
            return
        }
        let panel = panel
        let destination = FolderStackGeometry.dismissedFrame(from: placement.frame, edge: placement.chrome.edge)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(destination, display: true)
        } completionHandler: {
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            if event.window !== panel, !sourceIcon.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) {
                close(returnFocus: false)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            guard let self, !sourceIcon.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) else { return }
            close(returnFocus: false)
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 48:
            state.presentationFocused.toggle()
        case 49 where state.presentationFocused:
            state.choose(state.presentation == .grid ? .list : .grid)
        case 36 where !state.presentationFocused, 76 where !state.presentationFocused:
            state.openSelection()
        case 53:
            close(returnFocus: true)
        case 123 where state.presentationFocused:
            state.choose(.grid)
        case 124 where state.presentationFocused:
            state.choose(.list)
        case 123:
            state.select(by: -1)
        case 124:
            state.select(by: 1)
        case 125:
            state.select(by: state.presentation == .grid ? 5 : 1)
        case 126:
            state.select(by: state.presentation == .grid ? -5 : -1)
        default:
            return false
        }
        return true
    }
}
