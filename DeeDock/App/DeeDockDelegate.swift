import AppKit

/// Composition root; all docks and application-wide resources share this explicit lifetime.
@MainActor
final class DeeDockDelegate: NSObject, NSApplicationDelegate {
    /// First, so the consent store can tell a new install from an update before any other
    /// component writes its preferences.
    let analytics = Analytics.shared
    let windowAccess = WindowAccessController(service: SystemWindowAccessService())
    let screenCapture = ScreenCaptureAccessController(service: SystemScreenCaptureAccessService())
    private(set) lazy var coordinator = DockCoordinator(windowAccess: windowAccess, screenCapture: screenCapture)
    let updater = AppUpdater()
    let loginItems = LoginItemController(service: SystemLoginItemService())
    let menuBarIcon = MenuBarIconController()
    private(set) lazy var onboarding = OnboardingWindowController(
        loginItems: loginItems, settings: coordinator.settings, systemDockTuck: coordinator.systemDockTuck)
    /// Reapplies the alias if SwiftUI rebuilds the application menu.
    private var productAliasObserver: NSObjectProtocol?

    /// Xcode 27's JIT canvas uses the playground flag, while older preview hosts use the preview flag.
    private var isRunningForCanvasPreview: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningForCanvasPreview else { return }
        NSApp.setActivationPolicy(.accessory)
        analytics.contextInputs = { [weak self] in self?.analyticsContextInputs() ?? AnalyticsContextInputs() }
        Analytics.shared.start()
        AppDockPresence.shared.start()
        loginItems.refresh()
        windowAccess.refresh()
        screenCapture.refresh()
        coordinator.start()
        updater.start()
        coordinator.updateAwareness = updater.awareness
        coordinator.openUpdateTile = { [weak updater] item in
            if item.state == .installed {
                updater?.showWhatsNew(source: .dockTile)
            } else {
                updater?.checkForUpdates(source: .dockTile)
            }
        }
        updater.bindDesktop(
            isBusy: { [weak coordinator] in coordinator?.isUpdateAwarenessBlocked ?? true },
            isIdleBusy: { [weak coordinator] in coordinator?.updateIdleGate ?? UpdateIdleGate() },
            targetScreen: { [weak coordinator] in coordinator?.primaryEnabledScreen }
        )
        // After the docks exist, so a first-time reader sees the real thing behind the tour
        // rather than an empty desktop and a description of one.
        onboarding.presentIfNeeded()
        // The docks and the updater exist now, so the context can describe them.
        analytics.contextDidChange()
        guard ProductAlias.presentsFestiveName else { return }
        ProductAlias.applyRunningApplicationName()
        productAliasObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            self?.refreshProductAliasName()
        }
    }

    private func refreshProductAliasName() {
        ProductAlias.applyRunningApplicationName()
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
        if let productAliasObserver {
            NotificationCenter.default.removeObserver(productAliasObserver)
        }
        // First, so the macOS Dock comes back even if a later teardown step misbehaves.
        coordinator.systemDockTuck.restoreForTermination()
        updater.stop()
        AppDockPresence.shared.stop()
        onboarding.stop()
        loginItems.stop()
        windowAccess.stop()
        screenCapture.stop()
        coordinator.stop()
        Analytics.shared.stop()
    }
}
