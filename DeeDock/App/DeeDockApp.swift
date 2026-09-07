import SwiftUI

/// SwiftUI entry point exposing menu commands; the delegate owns the native dock lifecycle.
@main
struct DeeDockApp: App {
    @NSApplicationDelegateAdaptor(DeeDockDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            Button(.actionFocusDock) { delegate.coordinator.focusDock() }
                .disabled(!delegate.coordinator.canFocus)
            DockModesMenu(coordinator: delegate.coordinator)
            Divider()
            OpenDockSettingsButton()
                .keyboardShortcut(",")
            #if DIRECT_DISTRIBUTION
            CheckForUpdatesButton(updater: delegate.updater)
            #endif
            Button(.onboardingShowWelcome) { delegate.onboarding.present() }
            Divider()
            Button(.actionQuit) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            MenuBarExtraLabel(controller: delegate.menuBarIcon)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                OpenDockSettingsButton().keyboardShortcut(",")
            }
            CommandGroup(after: .appInfo) {
                #if DIRECT_DISTRIBUTION
                CheckForUpdatesButton(updater: delegate.updater)
                #endif
                Button(.onboardingShowWelcome) { delegate.onboarding.present() }
                Button(.actionFocusDock) { delegate.coordinator.focusDock() }
                .disabled(!delegate.coordinator.canFocus)
            }
        }
        Window(Text(.actionSettings), id: "settings") {
            DockSettingsView(store: delegate.coordinator.settings, profiles: delegate.coordinator.profiles,
                             loginItems: delegate.loginItems, menuBarIcon: delegate.menuBarIcon,
                             windowAccess: delegate.windowAccess,
                             screenCapture: delegate.screenCapture,
                             coordinator: delegate.coordinator)
            #if DIRECT_DISTRIBUTION
            .environment(\.appUpdater, delegate.updater)
            #endif
        }
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 820, height: 650)
    }
}

/// Isolated so Observation tracks the controller when the extra's label refreshes.
private struct MenuBarExtraLabel: View {
    let controller: MenuBarIconController

    var body: some View {
        Image(nsImage: DDockMenuBarMark.image(for: controller.style))
            .accessibilityLabel(Text(.appName))
    }
}
