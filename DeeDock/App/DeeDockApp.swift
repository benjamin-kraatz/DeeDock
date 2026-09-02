import SwiftUI

/// SwiftUI entry point exposing menu commands; the delegate owns the native dock lifecycle.
@main
struct DeeDockApp: App {
    @NSApplicationDelegateAdaptor(DeeDockDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            Button(.actionFocusDock) { delegate.controller?.focusDock() }
            OpenDockSettingsButton()
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
                Button(.actionFocusDock) { delegate.controller?.focusDock() }
            }
        }
        Settings {
            DockSettingsView(store: delegate.settings)
        }
    }
}
