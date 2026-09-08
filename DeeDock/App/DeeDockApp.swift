import SwiftUI

/// Selects an isolated scene host for canvas builds and the menu-bar app for normal launches.
@main
private enum DeeDockEntryPoint {
    /// Canvas hosts must not construct the menu-bar app or its live service graph.
    static func main() {
        #if DDOCK_CANVAS_HOST
        DeeDockPreviewApp.main()
        #else
        let environment = ProcessInfo.processInfo.environment
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1" {
            DeeDockPreviewApp.main()
        } else {
            DeeDockApp.main()
        }
        #endif
    }
}

/// Gives Xcode a normal scene to host previews without constructing the production delegate.
private struct DeeDockPreviewApp: App {
    var body: some Scene {
        WindowGroup { EmptyView() }
    }
}

/// Menu-bar scenes; the delegate owns the native dock lifecycle.
struct DeeDockApp: App {
    @NSApplicationDelegateAdaptor(DeeDockDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            Button(.actionFocusDock) { delegate.coordinator.focusDock() }
                .disabled(!delegate.coordinator.canFocus)
            Button(.portalFocusNext) { delegate.coordinator.focusNextPortal() }

            Button(.windowSearchTitle) { delegate.coordinator.searchWindows() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Text(delegate.coordinator.searchShortcutAvailable ? .windowSearchShortcutHelp : .windowSearchShortcutUnavailable)
            Button(.fusionTitle) { delegate.coordinator.showFusion() }
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
                Button(.portalFocusNext) { delegate.coordinator.focusNextPortal() }

                Button(.windowSearchTitle) { delegate.coordinator.searchWindows() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
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
            .background { SettingsWindowRegistration() }
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
