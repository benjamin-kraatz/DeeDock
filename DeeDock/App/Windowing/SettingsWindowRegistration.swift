import AppKit
import SwiftUI

/// Supplies the singleton Settings scene's window without discovering unrelated app windows.
struct SettingsWindowRegistration: NSViewRepresentable {
    func makeNSView(context: Context) -> RegistrationView { RegistrationView() }
    func updateNSView(_ nsView: RegistrationView, context: Context) {}

    final class RegistrationView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { ExplicitWindowPresenter.shared.registerSettings(window) }
        }
    }
}
