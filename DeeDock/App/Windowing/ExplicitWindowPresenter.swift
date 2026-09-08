import AppKit
import OSLog
import SwiftUI

/// Coordinates only requested window opens. Passive panels must not use this presenter.
/// App activation is asynchronous; track the intended window until activation and key focus agree.
@MainActor
final class ExplicitWindowPresenter {
    static let shared = ExplicitWindowPresenter()

    /// A focus owner may restore its previous app only while this request identity is unchanged.
    private(set) var generation = UUID()
    private weak var settingsWindow: NSWindow?
    private weak var target: NSWindow?
    private var awaitingSettings = false
    private var observers: [NSObjectProtocol] = []
    private var inputMonitor: Any?
    private var timeout: Task<Void, Never>?
    private var source = ""
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DDock", category: "WindowPresentation")

    /// Starts a request before SwiftUI creates or reuses the singleton Settings scene.
    func openSettings(using openWindow: OpenWindowAction, source: String) {
        begin(source: source)
        awaitingSettings = true
        if let settingsWindow {
            attach(settingsWindow)
        } else {
            openWindow(id: "settings")
        }
    }

    /// Registers the actual scene window without activating it during ordinary view updates.
    func registerSettings(_ window: NSWindow) {
        settingsWindow = window
        if awaitingSettings { attach(window) }
    }

    /// Reuses and deminiaturizes an owned window, then requests keyboard focus after menu tracking.
    func present(_ window: NSWindow, source: String = #fileID) {
        begin(source: source)
        attach(window)
    }

    /// Cancels deferred work when a controller hides a window without closing it.
    func cancel(_ window: NSWindow) {
        if target === window { finish("cancelled") }
    }

    private func begin(source: String) {
        finish("superseded")
        generation = UUID()
        self.source = source
        let request = generation
        timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self, generation == request else { return }
            finish("timed out")
        }
        log("requested")
    }

    private func attach(_ window: NSWindow) {
        AppDockPresence.shared.windowWillOpen(window)
        awaitingSettings = false
        target = window
        log("window attached")
        let request = generation
        observe(NSApplication.didBecomeActiveNotification, object: NSApp) { [weak self] in
            self?.log("app active")
            self?.scheduleFocus(request)
        }
        observe(NSApplication.didResignActiveNotification, object: NSApp) { [weak self] in
            self?.finish("app resigned")
        }
        // An activation notification may temporarily key another window. Only user input in
        // another window cancels the request; automatic key ordering must still be corrected.
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            if let self, let target, let window = event.window,
               window !== target, window.level != .popUpMenu {
                finish("another window selected")
            }
            return event
        }
        observe(NSWindow.willCloseNotification, object: window) { [weak self] in
            self?.finish("window closed")
        }
        observe(NSWindow.didBecomeKeyNotification, object: window) { [weak self] in
            self?.log("window key")
            self?.confirmFocus()
        }
        // Leave menu tracking and SwiftUI view attachment before mutating native window state.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, generation == request, target === window, let window else { return }
            if window.isMiniaturized { window.deminiaturize(nil) }
            guard generation == request, target === window else { return }
            window.makeKeyAndOrderFront(nil)
            guard generation == request, target === window else { return }
            NSApp.activate()
            scheduleFocus(request)
        }
    }

    private func scheduleFocus(_ request: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == request, let target, NSApp.isActive else { return }
            target.makeKeyAndOrderFront(nil)
            guard generation == request else { return }
            confirmFocus()
        }
    }

    private func confirmFocus() {
        guard NSApp.isActive, let target, target.isVisible, !target.isMiniaturized,
              target.isKeyWindow else { return }
        finish("focused")
    }

    private func observe(_ name: Notification.Name, object: AnyObject?, action: @escaping @MainActor () -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        })
    }

    private func finish(_ event: String) {
        if timeout != nil { log(event) }
        timeout?.cancel(); timeout = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
        target = nil
        awaitingSettings = false
    }

    private func log(_ event: String) {
        let window = target
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        logger.debug("version=\(version, privacy: .public), request=\(self.generation.uuidString, privacy: .public), \(self.source, privacy: .public): \(event, privacy: .public), foreground=\(pid), active=\(NSApp.isActive), window=\(window?.windowNumber ?? -1), visible=\(window?.isVisible ?? false), minimized=\(window?.isMiniaturized ?? false), key=\(window?.isKeyWindow ?? false), main=\(window?.isMainWindow ?? false)")
    }
}

extension OpenWindowAction {
    /// All Settings commands share scene identity and native activation coordination.
    func openDockSettings(source: String = #fileID) {
        ExplicitWindowPresenter.shared.openSettings(using: self, source: source)
    }
}
