import SwiftUI

/// SwiftUI entry point exposing menu commands; the delegate owns the native dock lifecycle.
@main
struct DeeDockApp: App {
    @NSApplicationDelegateAdaptor(DeeDockDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            Button(.actionFocusDock) { delegate.controller?.focusDock() }
            Divider()
            Button(.actionQuit) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Label { Text(.appName) } icon: { Image(systemName: "dock.rectangle") }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button(.actionFocusDock) { delegate.controller?.focusDock() }
            }
        }
    }
}
