import AppKit
import SwiftUI

/// An invisible AppKit view behind a swipeable row, so the swipe tracker can tell which row a
/// trackpad gesture started on.
///
/// Scroll events carry only a window location. Converting it into this view's own coordinates,
/// including the clip view of the scrolling list, is exact where SwiftUI frames would need a
/// guess about the hosting view's coordinate space. The view never takes clicks or focus and is
/// hidden from Accessibility. It registers while it is in a window and unregisters when it leaves.
struct NotificationFeedSwipeProbe: NSViewRepresentable {
    let id: NotificationFeedEntry.ID
    /// A folded stack swipes as a whole and reads "Clear All".
    let isStack: Bool
    /// Peeking cards behind a stack's front row do not swipe on their own.
    let isEnabled: Bool
    let tracker: NotificationFeedSwipeTracker

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        update(view)
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        update(view)
    }

    static func dismantleNSView(_ view: ProbeView, coordinator: ()) {
        view.detach()
    }

    private func update(_ view: ProbeView) {
        if view.id != id { view.detach() }
        view.id = id
        view.isStack = isStack
        view.isEnabled = isEnabled
        view.tracker = tracker
        view.attach()
    }

    final class ProbeView: NSView {
        var id: NotificationFeedEntry.ID?
        var isStack = false
        var isEnabled = false
        weak var tracker: NotificationFeedSwipeTracker?
        private weak var registeredTracker: NotificationFeedSwipeTracker?
        private var registeredID: NotificationFeedEntry.ID?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func isAccessibilityElement() -> Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { detach() } else { attach() }
        }

        /// Registers with the tracker while enabled and in a window, replacing a stale registration.
        func attach() {
            guard window != nil, isEnabled, let id, let tracker else { return detach() }
            if registeredID != id || registeredTracker !== tracker { detach() }
            tracker.register(self, id: id, isStack: isStack)
            registeredTracker = tracker
            registeredID = id
        }

        func detach() {
            if let registeredID { registeredTracker?.unregister(self, id: registeredID) }
            registeredTracker = nil
            registeredID = nil
        }
    }
}
