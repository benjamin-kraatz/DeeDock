import AppKit
import SwiftUI

private final class WindowWatchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// App-wide single-watch owner. A second request reveals the existing watch instead of replacing it.
@MainActor
final class WindowWatchController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var session: WindowWatchSession?
    private var displayObserver: NSObjectProtocol?

    func show(_ summary: ApplicationWindowSummary) {
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        let session = WindowWatchSession(summary: summary)
        let panel = WindowWatchPanel(contentRect: CGRect(x: 0, y: 0, width: 460, height: 680),
                                     styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = String(localized: .watchTitle)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: WindowWatchView(session: session))
        panel.delegate = self
        self.panel = panel
        self.session = session
        session.dismiss = { [weak self] in self?.stop() }
        positionPanel()
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.positionPanel() }
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { stop(); return false }

    /// Keep the persistent controls reachable after display removal, including small and negative-origin screens.
    private func positionPanel() {
        guard let panel, let screen = panel.screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let height = min(720, max(240, visible.height - 24))
        panel.setFrame(CGRect(x: visible.midX - 230, y: visible.midY - height / 2,
                              width: 460, height: height), display: true)
    }

    func stop() {
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        session?.dismiss = nil
        session?.stop()
        session = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.delegate = nil
        panel = nil
    }
}
