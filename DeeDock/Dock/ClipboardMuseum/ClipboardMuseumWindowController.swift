import AppKit
import SwiftUI

/// The museum's native window. Opened only by a menu command or Settings; closing it hands focus
/// back to the app that was in front before, when nothing else took focus meanwhile.
@MainActor
final class ClipboardMuseumWindowController: NSObject, NSWindowDelegate {
    private let store: ClipboardMuseumStore
    private let actions: ClipboardMuseumActions
    private var window: NSWindow?
    private var previousApplication: NSRunningApplication?
    private var focusGeneration = UUID()

    init(store: ClipboardMuseumStore, actions: ClipboardMuseumActions) {
        self.store = store
        self.actions = actions
    }

    func show(returningTo application: NSRunningApplication?) {
        if let window {
            ExplicitWindowPresenter.shared.present(window)
            focusGeneration = ExplicitWindowPresenter.shared.generation
            return
        }
        previousApplication = application ?? NSWorkspace.shared.frontmostApplication
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 980, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = String(localized: .clipboardMuseumTitle)
        window.isReleasedWhenClosed = false
        // Sidebar placards plus a framed piece and its placard need this much before wrapping.
        window.minSize = CGSize(width: 740, height: 500)
        window.contentViewController = NSHostingController(rootView: ClipboardMuseumView(store: store, actions: actions))
        window.delegate = self
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            let size = CGSize(width: min(980, frame.width), height: min(700, frame.height))
            window.setFrame(CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                   width: size.width, height: size.height), display: false)
        }
        self.window = window
        ExplicitWindowPresenter.shared.present(window)
        focusGeneration = ExplicitWindowPresenter.shared.generation
    }

    /// Closing drops the hosting view, which also drops any revealed content held in view state.
    func windowWillClose(_ notification: Notification) {
        window = nil
        if focusGeneration == ExplicitWindowPresenter.shared.generation,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
           let previousApplication, !previousApplication.isTerminated,
           previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
    }

    func stop() {
        previousApplication = nil
        window?.close()
    }
}
