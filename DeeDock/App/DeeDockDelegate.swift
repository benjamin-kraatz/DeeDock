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
    let menuBarIcon = MenuBarIconController()
    private(set) lazy var onboarding = OnboardingWindowController(
        loginItems: loginItems, settings: coordinator.settings)

    /// Xcode 27's JIT canvas uses the playground flag, while older preview hosts use the preview flag.
    private var isRunningForCanvasPreview: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningForCanvasPreview else { return }
        NSApp.setActivationPolicy(.accessory)
        AppDockPresence.shared.start()
        loginItems.refresh()
        windowAccess.refresh()
        screenCapture.refresh()
        coordinator.start()
        #if DIRECT_DISTRIBUTION
        updater.start()
        coordinator.updateAwareness = updater.awareness
        updater.bindDesktop(
            isBusy: { [weak coordinator] in coordinator?.isUpdateAwarenessBlocked ?? true },
            isIdleBusy: { [weak coordinator] in coordinator?.updateIdleGate ?? UpdateIdleGate() },
            targetScreen: { [weak coordinator] in coordinator?.primaryEnabledScreen }
        )
        #endif
        // After the docks exist, so a first-time reader sees the real thing behind the tour
        // rather than an empty desktop and a description of one.
        onboarding.presentIfNeeded()
    }

    /// Reopening the app restores an owned window without creating another scene.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !isRunningForCanvasPreview else { return false }
        if let window = AppDockPresence.shared.windowToReopen {
            ExplicitWindowPresenter.shared.present(window)
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !isRunningForCanvasPreview else { return }
        #if DIRECT_DISTRIBUTION
        updater.stop()
        #endif
        AppDockPresence.shared.stop()
        onboarding.stop()
        loginItems.stop()
        windowAccess.stop()
        screenCapture.stop()
        coordinator.stop()
    }
}
