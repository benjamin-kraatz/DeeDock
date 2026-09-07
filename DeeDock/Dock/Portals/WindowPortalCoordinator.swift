import AppKit

/// App-lifetime portal collection, independent of Peek dismissal and its discovery sessions.
@MainActor
final class WindowPortalCoordinator {
    static let maximumPortals = 4
    private var portals: [UUID: WindowPortalPanelController] = [:]
    private var order: [UUID] = []
    private var suspensionReasons: Set<String> = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// Returns false at the bound. The caller keeps Peek open and presents the localized limit message.
    func pin(_ source: ApplicationWindowSummary, appName: String, keyboard: Bool) -> Bool {
        guard portals.count < Self.maximumPortals else { return false }
        if portals.isEmpty { installObservers() }
        let id = UUID()
        let point = NSEvent.mouseLocation
        let portal = WindowPortalPanelController(source: source, appName: appName,
            origin: CGPoint(x: point.x + 20, y: point.y - 280))
        portals[id] = portal
        order.append(id)
        portal.onClose = { [weak self] in
            self?.portals[id] = nil
            self?.order.removeAll { $0 == id }
            if self?.portals.isEmpty == true { self?.removeObservers() }
        }
        portal.show(keyboard: keyboard)
        return true
    }

    func focusNext() {
        for _ in 0..<order.count {
            let id = order.removeFirst()
            order.append(id)
            guard let portal = portals[id], portal.isOpen else { continue }
            portal.focus()
            return
        }
    }

    func stop() {
        for portal in Array(portals.values) { portal.close() }
        portals.removeAll()
        removeObservers()
    }

    private func installObservers() {
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.portals.values.forEach { $0.repairPlacement() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "system"),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "screens"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session")
        ]
        for (pause, resume, reason) in pairs {
            observe(workspace, pause) { [weak self] in
                guard let self else { return }
                suspensionReasons.insert(reason)
                portals.values.forEach { $0.setSuspended(true) }
            }
            observe(workspace, resume) { [weak self] in
                guard let self else { return }
                suspensionReasons.remove(reason)
                portals.values.forEach { $0.setSuspended(!self.suspensionReasons.isEmpty); $0.repairPlacement() }
            }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        observers.append((center, token))
    }

    private func removeObservers() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        suspensionReasons.removeAll()
    }
}
