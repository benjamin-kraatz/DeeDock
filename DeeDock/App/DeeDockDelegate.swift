import AppKit

/// Composition root; all docks and application-wide resources share this explicit lifetime.
@MainActor
final class DeeDockDelegate: NSObject, NSApplicationDelegate {
    let coordinator = DockCoordinator()
    let loginItems = LoginItemController(service: SystemLoginItemService())

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loginItems.refresh()
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        loginItems.stop()
        coordinator.stop()
    }
}
