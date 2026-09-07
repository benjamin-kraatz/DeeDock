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
    private var duration: Double { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.32 }

    init(panel: DockPanel, state: LauncherState) { self.panel = panel; self.state = state }

    func open(origin: CGRect, target: CGRect, pins: [ApplicationReference], previousApplication: NSRunningApplication?) {
        guard !state.isPresented else { close(); return }
        generation = UUID(); closing = false
        let token = generation
        self.origin = origin
        self.previousApplication = previousApplication
        if self.previousApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier { self.previousApplication = nil }
        state.begin(pins: pins)
        state.close = { [weak self] in self?.close() }
        state.didOpen = { [weak self] in self?.close(restoreFocus: false) }
        state.isPresented = true; state.contentVisible = false
        panel.setFrame(origin, display: true)
        panel.acceptsKeyboardFocus = true
        // The passive dock only becomes key for views that request it. A searchable panel
        // needs ordinary field-editor focus, including after application activation settles.
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = false
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token, !self.closing else { return }
                self.panel.makeKeyAndOrderFront(nil)
                withAnimation(self.duration == 0 ? nil : .easeOut(duration: 0.16)) { self.state.contentVisible = true }
            }
        }
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
        if !animated || duration == 0 { finish(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(origin, display: true)
        } completionHandler: { MainActor.assumeIsolated { finish() } }
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
                case 125: state.moveSelection(by: state.layout == .grid ? state.navigationColumns : 1); return nil
                case 126: state.moveSelection(by: state.layout == .grid ? -state.navigationColumns : -1); return nil
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
        state.isPresented = false; state.contentVisible = false; state.end()
        state.didOpen = nil; didClose = nil; previousApplication = nil
    }
}
