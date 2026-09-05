import AppKit

/// Composition root; all docks and application-wide resources share this explicit lifetime.
@MainActor
final class DeeDockDelegate: NSObject, NSApplicationDelegate {
    let windowAccess = WindowAccessController(service: SystemWindowAccessService())
    let screenCapture = ScreenCaptureAccessController(service: SystemScreenCaptureAccessService())
    private(set) lazy var coordinator = DockCoordinator(windowAccess: windowAccess, screenCapture: screenCapture)
    #if DIRECT_DISTRIBUTION
    let updater = AppUpdater()
    #endif
    let loginItems = LoginItemController(service: SystemLoginItemService())
    private(set) lazy var onboarding = OnboardingWindowController(
        loginItems: loginItems, settings: coordinator.settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loginItems.refresh()
        windowAccess.refresh()
        screenCapture.refresh()
        coordinator.start()
        #if DIRECT_DISTRIBUTION
        updater.start()
        #endif
        // After the docks exist, so a first-time reader sees the real thing behind the tour
        // rather than an empty desktop and a description of one.
        onboarding.presentIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if DIRECT_DISTRIBUTION
        updater.stop()
        #endif
        onboarding.stop()
        loginItems.stop()
        windowAccess.stop()
        screenCapture.stop()
        coordinator.stop()
    }
}
