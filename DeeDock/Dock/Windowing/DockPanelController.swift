import AppKit

/// Owns one dock panel, display placement, event observation, and explicit keyboard focus.
/// The app delegate must pair `start()` with `stop()` before releasing this controller.
@MainActor
final class DockPanelController {
    private let store: DockStore
    private let interaction = DockInteraction()
    private let panel: DockPanel
    private var displayID: CGDirectDisplayID?
    private var eventMonitors: [Any] = []
    private var appObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var previousApplication: NSRunningApplication?
    private var lastExternalApplication: NSRunningApplication?

    /// Connects the live store and SwiftUI host without installing global event monitors.
    init(store: DockStore) {
        self.store = store
        panel = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        panel.title = String(localized: .appName)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = DockHostingView(rootView: DockView(store: store, interaction: interaction))
        interaction.geometryDidChange = { [weak self] in self?.updatePointer() }
        panel.keyboardHandler = { [weak self] event in self?.handleKey(event) ?? false }
        panel.resignedKey = { [weak self] in self?.endKeyboardFocus(restore: false) }
        store.itemsDidChange = { [weak self] in self?.placePanel() }
        store.applicationOpened = { [weak self] in self?.endKeyboardFocus(restore: false) }
    }

    /// Presents the panel and installs its event monitors and display/workspace observers.
    /// Call once per controller lifetime.
    func start() {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalApplication = frontmost
        }
        placePanel()
        panel.orderFrontRegardless()
        // Both monitors are needed: global events cover other apps, local events cover this app.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.updatePointer()
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.window === panel, store.keyboardFocus, handleKey(event) { return nil }
            updatePointer()
            return event
        }) { eventMonitors.append(monitor) }
        appObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.placePanel() } })
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.placePanel() }
            })
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                     object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                self?.lastExternalApplication = app
                self?.endKeyboardFocus(restore: false)
            }
        })
        updatePointer()
    }

    private func placePanel() {
        // NSScreen.main follows keyboard focus; the system display ID identifies the primary display.
        let primaryID = CGMainDisplayID()
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == primaryID
        }) else {
            panel.orderOut(nil)
            interaction.pointer = nil
            return
        }
        if displayID != primaryID { interaction.pointer = nil }
        displayID = primaryID
        interaction.layout = DockGeometry.layout(count: store.items.count,
                                                  favoriteCount: store.items.filter(\.isFavorite).count,
                                                  availableWidth: screen.visibleFrame.width)
        panel.setFrame(DockGeometry.panelFrame(visibleFrame: screen.visibleFrame,
                                               width: interaction.layout.viewportWidth), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
        updatePointer()
    }

    private func updatePointer() {
        let point = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        // AppKit is bottom-left-origin; SwiftUI reports top-left-origin geometry in logical points.
        let flipped = CGPoint(x: point.x, y: panel.frame.height - point.y)
        let inside = interaction.containsDockPoint(flipped)
        let inError = interaction.errorRect.contains(flipped)
        // Transparent window margins must pass through to the app beneath the dock.
        panel.ignoresMouseEvents = !inside && !inError
        let pointer = inside ? flipped : nil
        if interaction.pointer != pointer { interaction.pointer = pointer }
    }

    /// Explicitly grants keyboard focus and remembers the external app to restore on Escape.
    func focusDock() {
        previousApplication = lastExternalApplication
        panel.acceptsKeyboardFocus = true
        store.keyboardFocus = true
        store.selectedID = store.selectedID ?? store.items.first?.id
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard store.keyboardFocus else { return false }
        switch event.keyCode {
        case 123: store.moveSelection(by: -1)
        case 124: store.moveSelection(by: 1)
        case 36, 76: store.openSelection()
        case 53: endKeyboardFocus(restore: true)
        default: return false
        }
        return true
    }

    private func endKeyboardFocus(restore: Bool) {
        guard store.keyboardFocus else { return }
        // Clear the guard before resignKey, whose callback re-enters this method.
        store.keyboardFocus = false
        store.selectedID = nil
        panel.acceptsKeyboardFocus = false
        panel.resignKey()
        if restore, let previousApplication, !previousApplication.isTerminated {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
    }

    /// Removes every owned monitor/observer and closes the panel without changing system settings.
    func stop() {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors.removeAll()
        appObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        appObservers.removeAll()
        workspaceObservers.removeAll()
        interaction.geometryDidChange = nil
        panel.resignedKey = nil
        panel.keyboardHandler = nil
        panel.close()
        panel.contentView = nil
    }
}
