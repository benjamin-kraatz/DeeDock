import AppKit
import Observation
import SwiftUI

/// What the cursor hint currently says.
@MainActor @Observable
final class DockDropHintModel {
    /// Folder or volume name supplied by macOS.
    var destination = ""
    var moving = false
    /// Whether this target moves with Shift, so the copy hint can teach the modifier.
    var offersMove = false
    var visible = false
    /// The hint sits left of the cursor near the right screen edge; the capsule hugs that side.
    var trailing = false
}

/// A small label that follows the cursor during a file drag and says what releasing will do,
/// "Copy to “Stick”" or "Move to “Stick”". The drag image belongs to the source application, so
/// DOKK cannot caption it the way it captions its own drags; this panel stands in for that caption.
///
/// There is one cursor, so one shared hint. Drop targets call `show` from every drag update and
/// `hide` when the pointer leaves them. A watchdog hides a hint whose target stopped reporting,
/// for example because the drag ended over a window that never sent an exit.
@MainActor
final class DockDropHintController {
    static let shared = DockDropHintController()

    private static let size = CGSize(width: 340, height: 44)
    private static let cursorGap: CGFloat = 22
    private let model = DockDropHintModel()
    private var panel: NSPanel?
    private var watchdog: Task<Void, Never>?
    private var orderOutTask: Task<Void, Never>?

    /// Shows or refreshes the hint beside the cursor.
    func show(destination: String, moving: Bool, offersMove: Bool) {
        let panel = panel ?? makePanel()
        orderOutTask?.cancel(); orderOutTask = nil
        let placement = Self.frame(for: NSEvent.mouseLocation)
        model.trailing = placement.trailing
        panel.setFrame(placement.frame, display: false)
        if !panel.isVisible { panel.orderFrontRegardless() }
        let changed = model.destination != destination || model.moving != moving || model.offersMove != offersMove
        if changed || !model.visible {
            withAnimation(Self.animation) {
                model.destination = destination
                model.moving = moving
                model.offersMove = offersMove
                model.visible = true
            }
        }
        armWatchdog()
    }

    /// Hides after a short grace. Moving between neighboring targets (a folder row, the stack
    /// body) reports leave-then-enter; the grace keeps that from flickering the hint.
    func hide() {
        watchdog?.cancel(); watchdog = nil
        guard model.visible, orderOutTask == nil else { return }
        orderOutTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, let self else { return }
            withAnimation(Self.animation) { self.model.visible = false }
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
            orderOutTask = nil
        }
    }

    private static var animation: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.28, bounce: 0.2)
    }

    private func armWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// Right of the cursor and vertically centered on it, flipped to the left near a screen edge.
    private static func frame(for cursor: CGPoint) -> (frame: CGRect, trailing: Bool) {
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) }?.visibleFrame ?? .infinite
        var frame = CGRect(x: cursor.x + cursorGap, y: cursor.y - size.height / 2 - 14,
                           width: size.width, height: size.height)
        let trailing = frame.maxX > screen.maxX
        if trailing { frame.origin.x = cursor.x - cursorGap - size.width }
        frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - size.height)
        return (frame, trailing)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Above dock popovers, which sit at the pop-up menu level, so it stays readable over a stack.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let hosting = NSHostingView(rootView: DockDropHintView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        return panel
    }
}
