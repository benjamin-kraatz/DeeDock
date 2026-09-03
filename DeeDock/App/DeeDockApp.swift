import SwiftUI

/// SwiftUI entry point exposing menu commands; the delegate owns the native dock lifecycle.
@main
struct DeeDockApp: App {
    @NSApplicationDelegateAdaptor(DeeDockDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            Button(.actionFocusDock) { delegate.coordinator.focusDock() }
                .disabled(!delegate.coordinator.canFocus)
            OpenDockSettingsButton()
            Button(.onboardingShowWelcome) { delegate.onboarding.present() }
            Divider()
            Button(.actionQuit) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Label { Text(.appName) } icon: { Image(systemName: "dock.rectangle") }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                OpenDockSettingsButton().keyboardShortcut(",")
            }
            CommandGroup(after: .appInfo) {
                Button(.onboardingShowWelcome) { delegate.onboarding.present() }
                Button(.actionFocusDock) { delegate.coordinator.focusDock() }
                .disabled(!delegate.coordinator.canFocus)
            }
        }
        Settings {
            DockSettingsView(store: delegate.coordinator.settings, profiles: delegate.coordinator.profiles,
                             loginItems: delegate.loginItems, coordinator: delegate.coordinator)
        }
    }
}
