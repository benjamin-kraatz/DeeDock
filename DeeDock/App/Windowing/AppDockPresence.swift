import AppKit

/// Tracks DDock-owned app windows for its own dock, excluding transient and floating panels.
/// Membership follows open/close intent, so minimization, app hiding, and occlusion retain the icon.
@MainActor
final class AppDockPresence {
    static let shared = AppDockPresence()

    private let windows = NSHashTable<NSWindow>.weakObjects()
    private weak var lastOpenedWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var update: Task<Void, Never>?
    /// Catalogs refresh on membership changes without waiting for a Workspace app launch.
    static let didChangeNotification = Notification.Name("DDockOwnedWindowsDidChange")
    private var publishedPresence = false

    var hasOpenWindows: Bool { !windows.allObjects.isEmpty }

    /// Stable identity for the app tile; it uses the bundled app icon through ApplicationService.
    static var applicationID: String { Bundle.main.bundleIdentifier ?? Bundle.main.bundleURL.standardizedFileURL.path }

    static func representsCurrentApplication(_ reference: ApplicationReference) -> Bool {
        reference.id == applicationID
    }

    /// Installs one application-lifetime close observer. Preview hosts do not start this service.
    func start() {
        guard closeObserver == nil else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let window = notification.object as? NSWindow else { return }
                self?.windowDidCloseOrHide(window)
            }
        }
        scheduleUpdate()
    }

    /// Register before presentation; an already open window never adds a duplicate tile.
    func windowWillOpen(_ window: NSWindow) {
        guard closeObserver != nil, !(window is NSPanel), window.styleMask.contains(.titled) else { return }
        windows.add(window)
        lastOpenedWindow = window
        scheduleUpdate()
    }

    /// Explicit order-out counts as dismissal; application-wide Hide does not call this method.
    func windowDidCloseOrHide(_ window: NSWindow) {
        guard windows.contains(window) else { return }
        windows.remove(window)
        if lastOpenedWindow === window { lastOpenedWindow = nil }
        scheduleUpdate()
    }

    /// Defer catalog publication beyond SwiftUI attachment and native close callbacks. Opening
    /// a replacement window in the same action keeps the existing tile and its running order.
    private func scheduleUpdate() {
        update?.cancel()
        update = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            update = nil
            let present = hasOpenWindows
            guard present != publishedPresence else { return }
            publishedPresence = present
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    /// Clicking DDock in its own dock restores an existing window, including a minimized one.
    var windowToReopen: NSWindow? {
        lastOpenedWindow ?? windows.allObjects.first
    }

    /// Removes observation during app termination without publishing catalog changes mid-teardown.
    func stop() {
        update?.cancel(); update = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        windows.removeAllObjects()
        lastOpenedWindow = nil
        publishedPresence = false
    }
}
