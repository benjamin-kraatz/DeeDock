import AppKit
import SwiftUI

private final class VolumeCardPanel: NSPanel {
    var acceptsKeyboardFocus = false
    var escape: (() -> Void)?
    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { escape?() }
}

/// Buttons must work on the first click, because the card never activates DOKK.
private final class VolumeCardHostingView: NSHostingView<VolumeCardView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the native window for one volume card.
///
/// Unlike the folder-stack popover, a click on the dock passes through: clicking the volume tile
/// under an open card still opens its stack. The card sizes itself to its content and grows away
/// from the dock as its phase changes.
@MainActor
final class VolumeCardPanelController {
    let state: VolumeCardState
    private let panel: VolumeCardPanel
    private var anchor: DockPopoverAnchor
    private var contentHeight: CGFloat = 180
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var stopped = false
    /// A mouse-down anywhere outside the card, including on the dock.
    var outsideClick: (() -> Void)?
    var escape: (() -> Void)?

    init(state: VolumeCardState, anchor: DockPopoverAnchor, keyboard: Bool) {
        self.state = state
        self.anchor = anchor
        panel = VolumeCardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.acceptsKeyboardFocus = keyboard
        panel.setAccessibilityLabel(state.volume.name)
        let placement = Self.placement(anchor: anchor, contentHeight: contentHeight)
        state.chrome = placement.chrome
        let hosting = VolumeCardHostingView(rootView: VolumeCardView(state: state))
        // The panel frame comes from `DockPopoverGeometry`; the hosting view must not resize it.
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.escape = { [weak self] in self?.escape?() }
        panel.setFrame(placement.frame, display: false)
        state.heightChanged = { [weak self] height in self?.fit(contentHeight: height) }
    }

    var frame: CGRect { panel.frame }
    func contains(_ point: CGPoint) -> Bool { !stopped && panel.frame.contains(point) }

    func show() {
        installMonitors()
        let frame = panel.frame
        if state.reduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.setFrame(DockPopoverGeometry.dismissedFrame(from: frame, edge: anchor.edge), display: false)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(frame, display: true)
            }
        }
        if panel.acceptsKeyboardFocus { panel.makeKeyAndOrderFront(nil) }
    }

    /// Follows the tile when the dock moves, resizes, or scrolls.
    func update(_ anchor: DockPopoverAnchor) {
        guard !stopped else { return }
        self.anchor = anchor
        apply(animated: false)
    }

    func close() {
        guard !stopped else { return }
        stopped = true
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil; globalMonitor = nil
        outsideClick = nil; escape = nil; panel.escape = nil
        state.perform = nil; state.hovered = nil; state.heightChanged = nil
        let panel = panel
        guard !state.reduceMotion, panel.isVisible else {
            panel.orderOut(nil)
            panel.contentView = nil
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(DockPopoverGeometry.dismissedFrame(from: panel.frame, edge: self.anchor.edge),
                                      display: true)
        } completionHandler: {
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    /// Content height changes with the phase. The edge nearest the dock stays put, so the card
    /// grows away from its tile instead of jumping.
    private func fit(contentHeight height: CGFloat) {
        guard !stopped, height > 0, abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        apply(animated: panel.isVisible && !state.reduceMotion)
    }

    private func apply(animated: Bool) {
        let placement = Self.placement(anchor: anchor, contentHeight: contentHeight)
        state.chrome = placement.chrome
        guard placement.frame != panel.frame else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(placement.frame, display: true)
            }
        } else {
            panel.setFrame(placement.frame, display: true)
        }
    }

    private static func placement(anchor: DockPopoverAnchor, contentHeight: CGFloat) -> DockPopoverPlacement {
        let vertical = anchor.edge.isVertical
        let ideal = CGSize(width: VolumeCardView.width + (vertical ? DockPopoverGeometry.pointerDepth : 0),
                           height: contentHeight + (vertical ? 0 : DockPopoverGeometry.pointerDepth))
        return DockPopoverGeometry.placement(anchor: anchor, ideal: ideal)
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, event.window !== panel else { return event }
            outsideClick?()
            // Unlike stacks, the dock still receives the click.
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.outsideClick?()
        }
    }
}
