import AppKit

/// Composition root; all docks and application-wide resources share this explicit lifetime.
@MainActor
final class DeeDockDelegate: NSObject, NSApplicationDelegate {
    let coordinator = DockCoordinator()
    let loginItems = LoginItemController(service: SystemLoginItemService())
    private(set) lazy var onboarding = OnboardingWindowController(
        loginItems: loginItems, settings: coordinator.settings,
        openSettings: { SettingsWindowOpener.open() })

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loginItems.refresh()
        coordinator.start()
        // After the docks exist, so a first-time reader sees the real thing behind the tour
        // rather than an empty desktop and a description of one.
        onboarding.presentIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        onboarding.stop()
        loginItems.stop()
        coordinator.stop()
    }
}
