import AppKit
import ExtensionKit

/// The system's plugin list, where people turn each plugin on or off for DOKK.
///
/// `EXAppExtensionBrowserViewController` is drawn out of process by macOS. DOKK can place it in a
/// window but cannot style it, pre-select a plugin, or switch one on itself; that is the approval.
/// A running discovery monitor sees the change without a restart (the plugin spike's manual run),
/// and closing the window rescans anyway.
@MainActor
final class DockPluginApprovalWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    /// Called when the window closes, so the owner can rescan.
    var closed: (() -> Void)?

    var isOpen: Bool { window != nil }

    /// Shows the window, or brings it forward when it is already open. Activates DOKK: the person
    /// asked for it from Settings.
    func show() {
        if let window {
            ExplicitWindowPresenter.shared.present(window)
            return
        }
        let window = NSWindow(contentViewController: EXAppExtensionBrowserViewController())
        window.title = String(localized: .pluginsManageWindowTitle)
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 440))
        window.minSize = NSSize(width: 420, height: 320)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        ExplicitWindowPresenter.shared.present(window)
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        closed?()
    }
}
