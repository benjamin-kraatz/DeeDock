import AppKit
import SwiftUI

/// Scene identity for the System Settings Clone window.
enum SystemSettingsCloneWindow {
    static let id = "system-settings-clone"
}

/// Menu command that opens the clone window through the shared presenter.
struct OpenSystemSettingsCloneButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(.systemSettingsCloneMenu) {
            openWindow.openSystemSettingsClone()
        }
    }
}

/// Supplies the clone scene's window without discovering unrelated app windows.
struct SystemSettingsCloneWindowRegistration: NSViewRepresentable {
    func makeNSView(context: Context) -> RegistrationView { RegistrationView() }
    func updateNSView(_ nsView: RegistrationView, context: Context) {}

    final class RegistrationView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { ExplicitWindowPresenter.shared.registerSystemSettingsClone(window) }
        }
    }
}

extension OpenWindowAction {
    /// Clone commands share scene identity and native activation coordination.
    func openSystemSettingsClone(source: String = #fileID) {
        ExplicitWindowPresenter.shared.openSystemSettingsClone(using: self, source: source)
    }
}
