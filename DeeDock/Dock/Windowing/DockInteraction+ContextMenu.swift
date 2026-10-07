import Foundation

extension DockInteraction {
    /// Records a tile's context menu opening or closing, and spotlights the tile once the main
    /// thread is free to animate it.
    ///
    /// SwiftUI animations are timed by the clock but drawn on the main thread. A menu opens in the
    /// same turn as its delegate's `menuWillOpen`, along with any Window Peek it dismisses, and the
    /// chosen command runs right after `menuDidClose`. Starting the hop in either turn spends the
    /// spring behind that work, so the tile appears at its destination without travelling. Both
    /// changes therefore wait until work already queued on the main thread, plus anything that
    /// work queues, has run.
    ///
    /// Each deferred change rechecks ``contextMenuTracking``, so a menu that closes before its
    /// tile hops never spotlights it, and a newer menu keeps its own owner.
    /// - Parameters:
    ///   - tracking: Whether the tile's menu is open.
    ///   - target: The tile that owns the menu; nil for slots without an identity.
    func contextMenuTrackingChanged(_ tracking: Bool, target: DockEntryID?) {
        guard let target else { return }
        if tracking {
            contextMenuTracking = target
        } else if contextMenuTracking == target {
            contextMenuTracking = nil
        }
        afterPendingMainWork { [weak self] in
            guard let self else { return }
            if tracking {
                if contextMenuTracking == target { contextMenuTarget = target }
            } else if contextMenuTracking != target, contextMenuTarget == target {
                contextMenuTarget = nil
            }
        }
    }

    /// Runs `work` after the main queue drains what is queued now and what that queues in turn.
    ///
    /// Menu commands hop to the main queue themselves, so one async turn would run before them.
    private func afterPendingMainWork(_ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            DispatchQueue.main.async { work() }
        }
    }
}
