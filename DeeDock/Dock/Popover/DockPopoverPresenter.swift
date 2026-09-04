import Foundation

/// Keeps at most one dock popover open across every display and every feature.
///
/// Each feature coordinator owns its own panel and still enforces its own rules; this only
/// arbitrates between them, so opening a Shelf closes an open folder stack and the reverse.
/// `openChanged` reports whether *any* popover is showing, which the dock panels use to hold
/// themselves revealed.
@MainActor
final class DockPopoverPresenter {
    enum Kind: Hashable { case folderStack, shelf, sessionCapsules }

    private var dismiss: [Kind: () -> Void] = [:]
    private var openKind: Kind?
    var openChanged: ((Bool) -> Void)?

    var isOpen: Bool { openKind != nil }

    /// Registered once per feature coordinator at start-up.
    func register(_ kind: Kind, dismiss handler: @escaping () -> Void) {
        dismiss[kind] = handler
    }

    /// Closes any other feature's popover. Call before building a new panel.
    func prepareToOpen(_ kind: Kind) {
        for (other, handler) in dismiss where other != kind { handler() }
    }

    func didOpen(_ kind: Kind) {
        openKind = kind
        openChanged?(true)
    }

    func didClose(_ kind: Kind) {
        guard openKind == kind else { return }
        openKind = nil
        openChanged?(false)
    }

    /// Dismisses whatever is showing, without changing registrations.
    func closeAll() {
        for handler in dismiss.values { handler() }
    }

    func stop() {
        closeAll()
        dismiss.removeAll()
        openKind = nil
        openChanged = nil
    }
}
