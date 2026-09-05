#if DIRECT_DISTRIBUTION
import AppKit
import SwiftUI

/// Owns one resizable native update window. A close request goes through the driver's phase policy.
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    private let presentation: UpdatePresentation
    private let action: (UpdateAction, UUID) -> Void
    private let close: () -> Void
    // Capture artwork before installation; Sparkle may replace the bundle before its final callback.
    private let icon: NSImage?
    private var window: NSWindow?

    init(presentation: UpdatePresentation, icon: NSImage?, action: @escaping (UpdateAction, UUID) -> Void,
         close: @escaping () -> Void) {
        self.presentation = presentation
        self.icon = icon
        self.action = action
        self.close = close
    }

    func present(activate: Bool) {
        if window == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 580, height: 600),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = String(localized: .updatesWindowTitle)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 520, height: 540)
            window.delegate = self
            window.contentView = NSHostingView(rootView: UpdateWindowView(presentation: presentation,
                icon: icon, action: action, close: close))
            window.center()
            self.window = window
        }
        if activate {
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderFront(nil)
        }
    }

    /// Hiding progress retains the same session; dismissal never implies permission to install.
    func dismiss() { window?.orderOut(nil) }

    /// Releases the hosting hierarchy at process termination without invoking a user response.
    func stop() {
        window?.delegate = nil
        window?.close()
        window = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }
}
#endif
