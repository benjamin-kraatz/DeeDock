import AppKit
import OSLog

/// Shows the system Dock icon for open app windows, excluding transient and floating panels.
/// Membership follows open/close intent, so minimization, app hiding, and occlusion retain the icon.
@MainActor
final class AppDockPresence {
    static let shared = AppDockPresence()

    private let windows = NSHashTable<NSWindow>.weakObjects()
    private weak var lastOpenedWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var update: Task<Void, Never>?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DDock", category: "DockPresence")

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
        applyPolicy()
    }

    /// Promote before window activation; registering an already open window is idempotent.
    func windowWillOpen(_ window: NSWindow) {
        guard closeObserver != nil, !(window is NSPanel), window.styleMask.contains(.titled) else { return }
        update?.cancel(); update = nil
        windows.add(window)
        lastOpenedWindow = window
        applyPolicy()
    }

    /// Explicit order-out counts as dismissal; application-wide Hide does not call this method.
    func windowDidCloseOrHide(_ window: NSWindow) {
        guard windows.contains(window) else { return }
        windows.remove(window)
        if lastOpenedWindow === window { lastOpenedWindow = nil }
        update?.cancel()
        // willClose arrives before native teardown. A replacement window opened in the same
        // action cancels this update, avoiding a brief accessory/regular transition.
        update = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            update = nil
            applyPolicy()
        }
    }

    /// The system Dock icon reopens an existing window, including a minimized one.
    var windowToReopen: NSWindow? {
        lastOpenedWindow ?? windows.allObjects.first
    }

    private func applyPolicy() {
        let policy: NSApplication.ActivationPolicy = windows.allObjects.isEmpty ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        if !NSApp.setActivationPolicy(policy) {
            logger.error("Could not change system Dock presence to activation policy \(policy.rawValue)")
        }
    }

    /// Removes observation during app termination without changing activation mid-teardown.
    func stop() {
        update?.cancel(); update = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        windows.removeAllObjects()
        lastOpenedWindow = nil
    }
}
