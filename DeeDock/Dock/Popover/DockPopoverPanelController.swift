import AppKit
import SwiftUI

private final class DockPopoverPanel: NSPanel {
    var acceptsKeyboardFocus = false
    var keyboardHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if keyboardHandler?(event) != true { super.keyDown(with: event) }
    }
}

/// The transient panel every dock tile popover shares: a borderless non-activating window placed
/// inward from its tile, dismissed by an outside click, and animated along the dock's edge.
///
/// It owns the window, the dismissal monitors, and the show/close animation. What the panel
/// contains, which keys it understands, and what a close means to the rest of the app all stay
/// with the feature that created it.
@MainActor
final class DockPopoverPanelController<Content: View> {
    private let panel: DockPopoverPanel
    private let keyboard: Bool
    private let clickFocus: Bool
    private let reduceMotion: Bool
    private let ideal: CGSize
    private let chromeChanged: (DockPopoverChrome) -> Void
    private var placement: DockPopoverPlacement
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var stopped = false
    private var hosting: DockHostingView<Content>?
    var dragEntered: ((NSDraggingInfo) -> NSDragOperation)?
    var dragPerformed: ((NSDraggingInfo) -> Bool)?
    var dragExited: (() -> Void)?

    /// Enables file drops without changing keyboard eligibility during a spring-loaded reveal.
    func enableFileDrops() {
        hosting?.registerForDraggedTypes([.fileURL])
        hosting?.dragEntered = { [weak self] in self?.dragEntered?($0) ?? [] }
        hosting?.dragPerformed = { [weak self] in self?.dragPerformed?($0) ?? false }
        hosting?.dragExited = { [weak self] in self?.dragExited?() }
        hosting?.dragEnded = { [weak self] in self?.dragExited?() }
    }

    /// Feature-owned teardown, invoked once before the panel animates away.
    var willClose: (() -> Void)?
    /// Reported once with the caller's focus intent. Cleared before it runs, so it never repeats.
    var closed: ((Bool) -> Void)?
    /// Returns true when the feature consumed the key event.
    var keyHandler: ((NSEvent) -> Bool)?

    /// - Parameters:
    ///   - chromeChanged: Receives the resolved chrome before the content is built, and again on
    ///     every re-anchor, so the content view can draw its pointer in the right place.
    ///   - content: Built once, after the initial chrome has been published.
    init(anchor: DockPopoverAnchor, keyboard: Bool, clickFocus: Bool = false, ideal: CGSize = DockPopoverGeometry.idealSize,
         chromeChanged: @escaping (DockPopoverChrome) -> Void, content: () -> Content) {
        self.keyboard = keyboard
        self.clickFocus = clickFocus
        self.ideal = ideal
        self.chromeChanged = chromeChanged
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        placement = DockPopoverGeometry.placement(anchor: anchor, ideal: ideal)
        panel = DockPopoverPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.acceptsKeyboardFocus = keyboard
        chromeChanged(placement.chrome)
        let hosting = DockHostingView(rootView: content())
        self.hosting = hosting
        panel.contentView = hosting
        panel.keyboardHandler = { [weak self] in self?.keyHandler?($0) ?? false }
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
            panel.setFrame(DockPopoverGeometry.dismissedFrame(from: placement.frame, edge: placement.chrome.edge), display: false)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(placement.frame, display: true)
            }
        }
        if keyboard { panel.makeKeyAndOrderFront(nil) }
    }

    /// Follows its dock tile when the dock moves, resizes, or scrolls.
    func update(_ anchor: DockPopoverAnchor) {
        placement = DockPopoverGeometry.placement(anchor: anchor, ideal: ideal)
        chromeChanged(placement.chrome)
        panel.setFrame(placement.frame, display: true)
    }

    func close(returnFocus: Bool) {
        guard !stopped else { return }
        stopped = true
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil; globalMonitor = nil
        hosting?.unregisterDraggedTypes()
        hosting?.dragEntered = nil; hosting?.dragPerformed = nil
        hosting?.dragExited = nil; hosting?.dragEnded = nil
        dragEntered = nil; dragPerformed = nil; dragExited = nil
        willClose?()
        willClose = nil
        panel.keyboardHandler = nil
        keyHandler = nil
        let callback = closed
        closed = nil
        callback?(returnFocus)
        guard !reduceMotion, panel.isVisible else {
            panel.orderOut(nil)
            panel.contentView = nil
            return
        }
        let panel = panel
        let destination = DockPopoverGeometry.dismissedFrame(from: placement.frame, edge: placement.chrome.edge)
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
        // File panels route navigation before Quick Look's responder consumes Space/Escape.
        // Other popovers keep their original responder chain, including editable text fields.
        let localMask = clickFocus ? mask.union(.keyDown) : mask
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: localMask) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                guard event.window === panel else { return event }
                return keyHandler?(event) == true ? nil : event
            }
            guard event.window !== panel else {
                // Only an explicit click grants focus. Drag hover never reaches this path.
                if clickFocus {
                    panel.acceptsKeyboardFocus = true
                    panel.makeKeyAndOrderFront(nil)
                }
                return event
            }
            let consumesDockClick = event.window is DockPanel
            close(returnFocus: false)
            // A dock click dismisses the popover but must not reach the button underneath.
            if consumesDockClick { return nil }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.close(returnFocus: false)
        }
    }
}
