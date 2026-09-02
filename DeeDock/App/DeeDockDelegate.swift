import AppKit

/// Composition root that starts and tears down the store and native panel together.
@MainActor
final class DeeDockDelegate: NSObject, NSApplicationDelegate {
    private let store = DockStore()
    /// Shared by the settings scene and the single dock; no workspace work happens in Settings.
    let settings = DockSettingsStore(repository: DockSettingsRepository())
    /// Native dock owner exposed to the menu commands while the app is running.
    private(set) var controller: DockPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.start()
        let controller = DockPanelController(store: store, settings: settings)
        self.controller = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
        store.stop()
        controller = nil
    }
}
