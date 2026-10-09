import AppKit
import SwiftUI

/// Reports the window that hosts the Apps tab, so the model can tell Hub menus from menus in
/// other DOKK windows. Reports nil when the view leaves its window.
struct HubAppsWindowReader: NSViewRepresentable {
    let update: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.update = update
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.update = update
    }

    final class ReaderView: NSView {
        var update: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            update?(window)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
