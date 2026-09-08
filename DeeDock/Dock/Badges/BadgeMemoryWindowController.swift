import AppKit
import SwiftUI

@MainActor @Observable
final class BadgeMemoryPresentation {
    var path: String?
    var tab = 0
    var activationFailed = false
}

/// Explicitly opened native window. Hover never opens it or changes application focus.
@MainActor
final class BadgeMemoryWindowController: NSObject, NSWindowDelegate {
    private let memory: BadgeMemoryStore
    private let presentation = BadgeMemoryPresentation()
    private var window: NSWindow?
    private var previousApplication: NSRunningApplication?
    private var activationID = UUID()

    init(memory: BadgeMemoryStore) { self.memory = memory }

    func show(path: String? = nil, digest: Bool = false, returningTo application: NSRunningApplication? = nil) {
        presentation.path = path
        presentation.tab = digest ? 1 : 0
        presentation.activationFailed = false
        if let window { NSApp.activate(); window.makeKeyAndOrderFront(nil); return }
        previousApplication = application ?? NSWorkspace.shared.frontmostApplication
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 820, height: 620),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = String(localized: .badgeMemoryTitle)
        window.isReleasedWhenClosed = false
        // The list pane and a three-tile detail row both need room before either starts wrapping.
        window.minSize = CGSize(width: 640, height: 460)
        window.contentViewController = NSHostingController(rootView: BadgeMemoryView(
            memory: memory, presentation: presentation,
            activate: { [weak self] path in self?.activate(path) },
            close: { [weak self] in self?.window?.close() }))
        window.delegate = self
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            let size = CGSize(width: min(820, frame.width), height: min(620, frame.height))
            window.setFrame(CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                   width: size.width, height: size.height), display: false)
        }
        self.window = window
        NSApp.activate(); window.makeKeyAndOrderFront(nil)
    }

    private func activate(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension == "app", FileManager.default.fileExists(atPath: path) else {
            presentation.activationFailed = true; return
        }
        let id = UUID(); activationID = id
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] app, error in
            Task { @MainActor [weak self] in
                guard let self, window != nil, activationID == id else { return }
                if error != nil || app == nil { presentation.activationFailed = true }
                else { previousApplication = nil; window?.close() }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        activationID = UUID(); window = nil
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
           let previousApplication, !previousApplication.isTerminated,
           previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
    }

    func stop() { previousApplication = nil; window?.close() }
}
