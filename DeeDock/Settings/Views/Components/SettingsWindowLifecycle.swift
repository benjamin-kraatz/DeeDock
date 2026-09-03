import AppKit
import SwiftUI

/// Settings windows may close without destroying their SwiftUI tree; observe the actual owning window.
struct SettingsWindowLifecycle: NSViewRepresentable {
    let closed: () -> Void
    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) { view.closed = closed }
    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.stop() }

    final class ObserverView: NSView {
        var closed: (() -> Void)?
        private var observer: NSObjectProtocol?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { closed?(); return }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.closed?() }
            }
        }
        func stop() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil; closed?(); closed = nil
        }
    }
}
