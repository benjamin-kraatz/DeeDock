import AppKit

/// Composition root; all docks and application-wide resources share this explicit lifetime.
@MainActor
final class DeeDockDelegate: NSObject, NSApplicationDelegate {
    let coordinator = DockCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) { coordinator.stop() }
}
