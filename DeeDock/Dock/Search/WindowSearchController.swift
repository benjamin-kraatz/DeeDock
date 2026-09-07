import AppKit
import SwiftUI

/// An explicitly opened search window, placed on the pointer's display without depending on dock edge.
@MainActor
final class WindowSearchController: NSObject, NSWindowDelegate {
    private let capsules: SessionCapsuleController
    private var window: NSWindow?
    private var state: WindowSearchState?
    private var previousApplication: NSRunningApplication?
    private var restoresFocus = true

    init(capsules: SessionCapsuleController) { self.capsules = capsules }

    func show() {
        if let window { NSApp.activate(); window.makeKeyAndOrderFront(nil); return }
        previousApplication = NSWorkspace.shared.frontmostApplication
        restoresFocus = true
        let state = WindowSearchState(capsules: capsules)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = String(localized: .windowSearchTitle)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: WindowSearchView(state: state))
        window.delegate = self
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = CGSize(width: min(760, visible.width), height: min(640, visible.height))
            window.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                   width: size.width, height: size.height), display: false)
        }
        self.state = state; self.window = window
        state.close = { [weak self] in
            // If activation already moved focus to a source app, do not restore the prior application.
            guard let self else { return }
            restoresFocus = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            self.window?.close()
        }
        state.activated = { [weak self] in self?.restoresFocus = false; self?.window?.close() }
        NSApp.activate(); window.makeKeyAndOrderFront(nil)
        state.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        state?.stop(); state = nil; window = nil
        if restoresFocus, let previousApplication, !previousApplication.isTerminated,
           previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
    }

    func reloadCapsules() {
        if let id = state?.openedCapsule?.id { state?.openedCapsule = capsules.capsules.first { $0.id == id } }
        state?.rank()
    }

    func stop() { restoresFocus = false; window?.close() }
}
