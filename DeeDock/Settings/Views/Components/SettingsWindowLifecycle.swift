import AppKit
import SwiftUI

/// Settings windows can close and reopen while retaining their SwiftUI tree. Track the actual
/// owning window's activity so temporary overlays cannot survive closing, minimization, or app switching.
struct SettingsWindowLifecycle: NSViewRepresentable {
    let closed: () -> Void
    var activityChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) {
        view.closed = closed
        view.activityChanged = activityChanged
        view.scheduleActivityUpdate()
    }
    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.stop() }

    final class ObserverView: NSView {
        var closed: (() -> Void)?
        var activityChanged: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var activityUpdate: Task<Void, Never>?
        private var lastActivity: Bool?
        private var closing = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            closing = false
            guard let window else {
                closed?()
                scheduleActivityUpdate()
                return
            }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.closing = true
                    self?.lastActivity = nil
                    self?.closed?()
                    self?.scheduleActivityUpdate()
                }
            })
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                    MainActor.assumeIsolated {
                        if notification.name == NSWindow.didBecomeKeyNotification { self?.closing = false }
                        self?.scheduleActivityUpdate()
                    }
                })
            }
            for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                         NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                observers.append(center.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleActivityUpdate() }
                })
            }
            scheduleActivityUpdate()
        }

        /// Defer SwiftUI state publication until the representable update or native notification finishes.
        /// Coalescing also prevents a queued close update from hiding an already reopened Settings window.
        func scheduleActivityUpdate() {
            activityUpdate?.cancel()
            activityUpdate = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                defer { activityUpdate = nil }
                let active = !closing && window?.isVisible == true && window?.isKeyWindow == true
                    && window?.isMiniaturized == false && NSApp.isActive && !NSApp.isHidden
                guard lastActivity != active else { return }
                lastActivity = active
                activityChanged?(active)
            }
        }

        private func removeObservers() {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
        }

        func stop() {
            activityUpdate?.cancel(); activityUpdate = nil
            removeObservers()
            closed?()
            closed = nil; activityChanged = nil; lastActivity = nil
        }
    }
}
