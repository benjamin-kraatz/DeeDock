import AppKit
import os
import SwiftUI

private let popoverLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DeeDock", category: "Popover")

private final class DockPopoverPanel: NSPanel {
    var acceptsKeyboardFocus = false
    var keyboardHandler: ((NSEvent) -> Bool)?
    var resignedKey: (() -> Void)?
    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { false }
    override func resignKey() {
        super.resignKey()
        resignedKey?()
    }
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
    private let activates: Bool
    private let remoteContent: Bool
    private let reduceMotion: Bool
    private var ideal: CGSize
    private let outline: ((DockPopoverChrome) -> DockPopoverShape)?
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

    /// A feature may keep its draft alive while an owned native picker handles outside clicks.
    /// Explicit close and display teardown still dismiss the panel.
    var canDismissForOutsideClick: (() -> Bool)?

    /// Feature-owned teardown, invoked once before the panel animates away.
    var willClose: (() -> Void)?
    /// Reported once with the caller's focus intent. Cleared before it runs, so it never repeats.
    var closed: ((Bool) -> Void)?
    /// Returns true when the feature consumed the key event.
    var keyHandler: ((NSEvent) -> Bool)?
    /// Called when the panel stops being key, for features that close once focus moves elsewhere.
    var resignedKey: (() -> Void)?

    /// - Parameters:
    ///   - activates: Activates DOKK through ``ExplicitWindowPresenter`` when shown, so a text field
    ///     gets ordinary field-editor focus. Implies `keyboard`.
    ///   - windowShadow: Whether AppKit draws the window shadow. Liquid Glass content draws its own,
    ///     and AppKit would outline the whole rectangular window around it, so glass panels pass false.
    ///   - outline: The visible outline of content that draws nothing the window server can hit-test,
    ///     such as Liquid Glass with no fill beneath it. Without it, clicks and scrolls on the panel's
    ///     transparent pixels reach the window behind and count as outside clicks. With it, the panel
    ///     receives every pointer event over its frame, and only clicks outside the outline dismiss.
    ///   - remoteContent: The content includes a view another process draws, such as a plugin's
    ///     ExtensionKit scene. That process can receive clicks on its view in a window of its own,
    ///     so DOKK sees them as clicks in another window or another app. With this set, a click
    ///     inside the panel's body counts as a click on the panel, whichever window received it.
    ///   - chromeChanged: Receives the resolved chrome before the content is built, and again on
    ///     every re-anchor, so the content view can draw its pointer in the right place.
    ///   - content: Built once, after the initial chrome has been published.
    init(anchor: DockPopoverAnchor, keyboard: Bool, clickFocus: Bool = false, activates: Bool = false,
         remoteContent: Bool = false, windowShadow: Bool = true, ideal: CGSize = DockPopoverGeometry.idealSize,
         outline: ((DockPopoverChrome) -> DockPopoverShape)? = nil,
         chromeChanged: @escaping (DockPopoverChrome) -> Void, content: () -> Content) {
        self.keyboard = keyboard || activates
        self.clickFocus = clickFocus
        self.activates = activates
        self.remoteContent = remoteContent
        self.ideal = ideal
        self.outline = outline
        self.chromeChanged = chromeChanged
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        placement = DockPopoverGeometry.placement(anchor: anchor, ideal: ideal)
        panel = DockPopoverPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = windowShadow
        // A non-opaque window passes events on fully transparent pixels to the window behind it,
        // unless this is set explicitly. Glass composites outside the window's backing, so the gaps
        // between glass content read as transparent; the outline check below takes over instead.
        if outline != nil { panel.ignoresMouseEvents = false }
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.acceptsKeyboardFocus = keyboard || activates
        chromeChanged(placement.chrome)
        let hosting = DockHostingView(rootView: content())
        self.hosting = hosting
        panel.contentView = hosting
        panel.keyboardHandler = { [weak self] in self?.keyHandler?($0) ?? false }
        panel.resignedKey = { [weak self] in self?.resignedKey?() }
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
        if activates { ExplicitWindowPresenter.shared.present(panel) }
        else if keyboard { panel.makeKeyAndOrderFront(nil) }
    }

    /// Follows its dock tile when the dock moves, resizes, or scrolls.
    func update(_ anchor: DockPopoverAnchor) {
        placement = DockPopoverGeometry.placement(anchor: anchor, ideal: ideal)
        chromeChanged(placement.chrome)
        panel.setFrame(placement.frame, display: true)
    }

    /// Changes the size the panel asks for, keeping it attached to `anchor`. Animates the frame
    /// unless Reduce Motion is on. Used by plugin panels, whose plugin can ask for a new size.
    func resize(to ideal: CGSize, anchor: DockPopoverAnchor) {
        guard !stopped, ideal != self.ideal else { return }
        self.ideal = ideal
        placement = DockPopoverGeometry.placement(anchor: anchor, ideal: ideal)
        chromeChanged(placement.chrome)
        guard !reduceMotion, panel.isVisible else {
            panel.setFrame(placement.frame, display: true)
            return
        }
        let frame = placement.frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.9, 0.3, 1)
            panel.animator().setFrame(frame, display: true)
        }
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
        canDismissForOutsideClick = nil
        if activates { ExplicitWindowPresenter.shared.cancel(panel) }
        panel.keyboardHandler = nil
        panel.resignedKey = nil
        keyHandler = nil
        resignedKey = nil
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

    /// Whether a click on the panel lands inside the visible outline. Panels without an outline
    /// receive only the clicks the window server routes to their drawn pixels, so every one counts.
    private func outlineContains(_ event: NSEvent) -> Bool {
        guard let outline else { return true }
        // The shape is drawn in SwiftUI's top-left space; window coordinates start at the bottom left.
        let size = panel.frame.size
        let point = CGPoint(x: event.locationInWindow.x, y: size.height - event.locationInWindow.y)
        return outline(placement.chrome).path(in: CGRect(origin: .zero, size: size)).contains(point)
    }

    /// The panel's body in screen coordinates: its frame without the pointer strip on the dock's
    /// side, whose transparent corners let clicks through to the window behind.
    private var bodyFrame: CGRect {
        let frame = panel.frame
        let depth = DockPopoverGeometry.pointerDepth
        switch placement.chrome.edge {
        case .bottom: return CGRect(x: frame.minX, y: frame.minY + depth, width: frame.width, height: frame.height - depth)
        case .top: return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - depth)
        case .left: return CGRect(x: frame.minX + depth, y: frame.minY, width: frame.width - depth, height: frame.height)
        case .right: return CGRect(x: frame.minX, y: frame.minY, width: frame.width - depth, height: frame.height)
        }
    }

    /// Whether a click another window received landed on remote content inside this panel.
    /// - Parameter location: The click in screen coordinates.
    private func isRemoteContentClick(at location: CGPoint) -> Bool {
        guard remoteContent, panel.isVisible, bodyFrame.contains(location) else { return false }
        popoverLogger.debug("Kept a click on the panel's remote content")
        return true
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
            if event.window === panel, outlineContains(event) {
                // Only an explicit click grants focus. Drag hover never reaches this path.
                if clickFocus {
                    panel.acceptsKeyboardFocus = true
                    panel.makeKeyAndOrderFront(nil)
                }
                return event
            }
            // The click went to another of DOKK's windows over the panel, not to the panel itself.
            // It still belongs to the plugin's scene, and its focus stays where that window put it.
            if let window = event.window, window !== panel, !(window is DockPanel),
               isRemoteContentClick(at: window.convertPoint(toScreen: event.locationInWindow)) {
                return event
            }
            guard canDismissForOutsideClick?() != false else { return event }
            // A dock click dismisses the popover but must not reach the button underneath.
            // A click on the panel's margin outside the outline dismisses without reaching the content.
            let consumesClick = event.window is DockPanel || event.window === panel
            close(returnFocus: false)
            if consumesClick { return nil }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            guard let self, canDismissForOutsideClick?() != false else { return }
            // A global event carries no window of DOKK's; the pointer says where the click was.
            guard !isRemoteContentClick(at: NSEvent.mouseLocation) else { return }
            close(returnFocus: false)
        }
    }
}
