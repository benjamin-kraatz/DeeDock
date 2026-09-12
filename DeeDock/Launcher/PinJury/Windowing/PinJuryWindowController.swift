import AppKit
import SwiftUI

/// A normal app window per display. Only explicit commands present or focus a hearing.
@MainActor
final class PinJuryWindowController: NSObject, NSWindowDelegate {
    let state: PinJuryState
    private var window: NSWindow?
    private var previousApplication: NSRunningApplication?
    private var focusGeneration = UUID()
    private let historySettingsRequested: () -> Void

    init(state: PinJuryState, historySettingsRequested: @escaping () -> Void) {
        self.state = state
        self.historySettingsRequested = historySettingsRequested
    }

    func show(returningTo application: NSRunningApplication?) {
        if let window {
            ExplicitWindowPresenter.shared.present(window)
            focusGeneration = ExplicitWindowPresenter.shared.generation
            return
        }
        state.reload()
        previousApplication = application ?? NSWorkspace.shared.frontmostApplication
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 940, height: 760),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = String(localized: .pinJuryTitle)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 760, height: 600)
        window.contentViewController = NSHostingController(rootView: PinJuryWindowContent(
            state: state, historySettingsRequested: historySettingsRequested,
            close: { [weak self] in self?.window?.close() }))
        window.delegate = self
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            let size = CGSize(width: min(940, frame.width), height: min(760, frame.height))
            window.setFrame(CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                   width: size.width, height: size.height), display: false)
        }
        self.window = window
        ExplicitWindowPresenter.shared.present(window)
        focusGeneration = ExplicitWindowPresenter.shared.generation
    }

    func windowWillClose(_ notification: Notification) {
        state.clear()
        window = nil
        if focusGeneration == ExplicitWindowPresenter.shared.generation,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
           let previousApplication, !previousApplication.isTerminated,
           previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
    }

    /// Sleep, session lock, display removal and termination end generation and release evidence.
    func stop() {
        previousApplication = nil
        state.clear()
        window?.close()
    }
}

private struct PinJuryWindowContent: View {
    let state: PinJuryState
    let historySettingsRequested: () -> Void
    let close: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        PinJuryView(state: state) {
            historySettingsRequested()
            openWindow.openDockSettings()
        }
        .onExitCommand {
            if state.isBusy { state.cancel() }
            else if state.phase == .awaitingDecision { state.reject() }
            else { close() }
        }
    }
}
