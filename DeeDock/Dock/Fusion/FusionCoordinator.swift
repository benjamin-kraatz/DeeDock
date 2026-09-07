import AppKit
import SwiftUI

/// A persistent app-owned tray, independent of transient dock popovers and display lifetimes.
/// Hover never activates it. Explicit selection and menu actions may give its controls focus.
@MainActor
final class FusionCoordinator: NSObject, NSWindowDelegate {
    let state: FusionState
    private var panel: FusionPanel?
    private var displayObserver: NSObjectProtocol?
    private weak var returnPanel: DockPanelController?
    var restoreDockFocus: ((DockPanelController) -> Void)?
    private var returnsToDock = false
    private var previousApplication: NSRunningApplication?

    init(shelf: ShelfController) { state = FusionState(shelf: shelf) }

    func show(from dock: DockPanelController? = nil, keyboard: Bool = false, matching window: ApplicationWindowSummary? = nil) {
        returnPanel = dock
        returnsToDock = keyboard
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = NSWorkspace.shared.frontmostApplication
        }
        if panel == nil {
            let next = FusionPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 720),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            next.title = String(localized: .fusionTitle)
            next.isReleasedWhenClosed = false
            next.hidesOnDeactivate = false
            next.isFloatingPanel = true
            next.level = .floating
            next.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            next.contentView = NSHostingView(rootView: FusionPanelView(state: state, close: { [weak self] in self?.hide() }))
            next.delegate = self
            next.escape = { [weak self] in self?.hide() }
            next.center()
            panel = next
            displayObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.fitToVisibleScreen() }
            }
        }
        state.expireIfNeeded()
        fitToVisibleScreen(preferred: NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) })
        panel?.makeKeyAndOrderFront(nil)
        if let window { state.pick(matching: window) }
        else if state.sources.isEmpty && !state.isBusy && state.draft == nil { state.pick() }
    }

    /// Clamp in AppKit screen points, including negative display origins and removed displays.
    private func fitToVisibleScreen(preferred: NSScreen? = nil) {
        guard let panel, let screen = preferred ?? panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        panel.setFrame(frame, display: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    private func hide() {
        guard state.activity != .saving else { return }
        state.suspend()
        panel?.orderOut(nil)
        if returnsToDock, let returnPanel { restoreDockFocus?(returnPanel) }
        else { previousApplication?.activate() }
    }

    /// Release captured context when the machine sleeps or the user session locks.
    func suspend() {
        state.suspend()
        panel?.orderOut(nil)
    }

    func stop() {
        state.reset()
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        panel?.orderOut(nil)
        panel?.delegate = nil
        panel = nil
        returnPanel = nil
        previousApplication = nil
        restoreDockFocus = nil
    }
}

private final class FusionPanel: NSPanel {
    var escape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { escape?() }
}
