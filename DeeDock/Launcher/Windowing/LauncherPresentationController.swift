import AppKit
import SwiftUI

/// Expands the existing dock panel, preserving its native material and screen ownership.
/// Scoped monitors exist only while open. Generation checks prevent stale morph completions restoring a closed panel.
@MainActor
final class LauncherPresentationController {
    let state: LauncherState
    private let panel: DockPanel
    var origin = CGRect.zero
    var didClose: (() -> Void)?
    private var previousApplication: NSRunningApplication?
    private var monitors: [Any] = []
    private var generation = UUID()
    private var closing = false
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Expanding passes the expanded rect by a few percent and settles back onto it.
    private let openSpring = Animation.spring(response: 0.42, dampingFraction: 0.72)
    /// Collapsing is quicker and lands on the dock's rect with only a trace of a bounce.
    private let closeSpring = Animation.spring(response: 0.28, dampingFraction: 0.86)

    init(panel: DockPanel, state: LauncherState) { self.panel = panel; self.state = state }

    func open(origin: CGRect, target: CGRect, dockWindow: CGRect, pins: [ApplicationReference],
              previousApplication: NSRunningApplication?) {
        guard !state.isPresented else { close(); return }
        generation = UUID(); closing = false
        let token = generation
        self.origin = origin
        self.previousApplication = previousApplication
        if self.previousApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier { self.previousApplication = nil }
        state.begin(pins: pins, foregroundID: self.previousApplication?.bundleIdentifier)
        state.close = { [weak self] in self?.close() }
        state.didOpen = { [weak self] in self?.close(restoreFocus: false) }
        state.isPresented = true; state.contentVisible = false; state.expanded = false
        // The panel takes its final frame up front and never resizes again while it is open. The
        // window is transparent outside the glass, so its size is not what the morph shows: the
        // glass rect grows inside it instead, which leaves every control laid out where it lands.
        let window = LauncherPanelFrame.presentation(origin: origin, target: target,
                                                     screen: panel.screen?.visibleFrame ?? origin.union(target))
        state.dockRect = Self.local(origin, in: window)
        state.contentRect = Self.local(target, in: window)
        let dock = Self.local(dockWindow, in: window)
        state.dockContentOffset = CGSize(width: dock.minX, height: dock.minY)
        state.morph = 0
        LauncherPanelFrame.set(window, on: panel)
        panel.acceptsKeyboardFocus = true
        // The passive dock only becomes key for views that request it. A searchable panel
        // needs ordinary field-editor focus, including after application activation settles.
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = false
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        if reduceMotion {
            state.expanded = true; state.morph = 1
            state.contentVisible = true
            return
        }
        // Shape and contents share one animation. The dock's contents dissolve over its first
        // third and the launcher's resolve over its second half, so neither is a fade running
        // beside the morph - both are the morph.
        state.contentVisible = true
        withAnimation(openSpring) { state.expanded = true; state.morph = 1 }
    }

    func close(animated: Bool = true, restoreFocus: Bool = true) {
        guard state.isPresented, !closing || !animated else { return }
        closing = true; generation = UUID()
        let token = generation
        removeMonitors()
        state.cancelRobi()
        state.contentVisible = false
        let finish = { [weak self] in
            guard let self, generation == token else { return }
            state.isPresented = false
            state.end()
            panel.acceptsKeyboardFocus = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.resignKey()
            closing = false
            didClose?()
            if restoreFocus, let previousApplication, !previousApplication.isTerminated {
                previousApplication.activate(options: [])
            }
            previousApplication = nil
        }
        if !animated || reduceMotion { state.expanded = false; state.morph = 0; finish(); return }
        withAnimation(closeSpring) { state.expanded = false; state.morph = 0 } completion: { finish() }
    }

    /// Converts a screen rect into the presentation window's top-left origin, y-down coordinates.
    private static func local(_ rect: CGRect, in window: CGRect) -> CGRect {
        CGRect(x: rect.minX - window.minX, y: window.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private func installMonitors() {
        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouse, handler: { [weak self] _ in
            self?.close(restoreFocus: false)
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mouse.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.window === panel,
               let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() {
                return event // Input-method candidates own arrows, Return, and Escape until composition ends.
            }
            if event.type == .keyDown, event.window === panel, event.keyCode == 53 { close(); return nil }
            // The window is larger than the glass while the launcher is open, so a click on the
            // transparent margin has to dismiss the way a click outside the window would.
            if mouse.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue)), event.window === panel,
               state.contentRect != .zero {
                let point = CGPoint(x: event.locationInWindow.x, y: panel.frame.height - event.locationInWindow.y)
                if !state.contentRect.contains(point) { close(restoreFocus: false); return nil }
            }
            if event.type == .keyDown, event.window === panel, event.keyCode == 48 {
                state.keyboardNavigationActive = false; state.selectedID = nil
            }
            if event.type == .keyDown, event.window === panel, state.contentVisible,
               state.keyboardNavigationActive, [36, 76].contains(event.keyCode),
               event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                state.openSelection(); return nil
            }
            if mouse.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue)), event.window === panel {
                state.keyboardNavigationActive = false; state.selectedID = nil
            }
            // The native field editor consumes arrow keys before SwiftUI's key handlers.
            // Once vertical navigation begins, arrows select results while typing still edits the query.
            if event.type == .keyDown, event.window === panel, state.contentVisible,
               panel.firstResponder is NSTextView,
               event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                switch event.keyCode {
                case 125: state.moveSelection(by: state.usesGridNavigation ? state.navigationColumns : 1); return nil
                case 126: state.moveSelection(by: state.usesGridNavigation ? -state.navigationColumns : -1); return nil
                case 123 where state.keyboardNavigationActive: state.moveSelection(by: -1); return nil
                case 124 where state.keyboardNavigationActive: state.moveSelection(by: 1); return nil
                default: break
                }
            }
            if mouse.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue)), let window = event.window, window !== panel {
                // Native popup menus own their own windows and must not dismiss the launcher.
                if window.level != .popUpMenu { close(restoreFocus: false) }
            }
            return event
        }) { monitors.append(monitor) }
    }

    private func removeMonitors() { monitors.forEach(NSEvent.removeMonitor); monitors = [] }

    func stop() {
        generation = UUID(); removeMonitors()
        state.isPresented = false; state.contentVisible = false; state.expanded = false
        state.morph = 0; state.end()
        state.didOpen = nil; didClose = nil; previousApplication = nil
    }
}
