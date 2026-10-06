import AppKit
import Observation

/// Presentation state for one open notification feed popover.
///
/// The entries themselves stay in ``NotificationFeedStore``; this holds only what belongs to the
/// open panel: its chrome, keyboard selection, which entries were new when it opened, and the
/// commands the coordinator handles.
@MainActor @Observable
final class NotificationFeedPanelState {
    var chrome = DockPopoverChrome(edge: .bottom, attachment: 190)
    /// The keyboard selection. Nil until the person presses an arrow key.
    var selection: NotificationFeedEntry.ID?
    /// Entries that were unread when the panel opened. They keep their marker while it stays open.
    let unreadOnOpen: Set<NotificationFeedEntry.ID>
    /// Set when the person cleared the feed while this panel was open. Reported on close.
    private(set) var cleared = false

    @ObservationIgnored var open: ((NotificationFeedEntry) -> Void)?
    @ObservationIgnored var copy: ((NotificationFeedEntry) -> Void)?
    @ObservationIgnored var remove: ((NotificationFeedEntry.ID) -> Void)?
    @ObservationIgnored var clearAll: (() -> Void)?
    /// Routes Settings to the notification feed page; the view then opens the window.
    @ObservationIgnored var prepareSettings: (() -> Void)?
    /// The single application a banner's name resolves to, if any.
    @ObservationIgnored var application: ((NotificationFeedEntry) -> ApplicationReference?)?
    @ObservationIgnored var icon: ((ApplicationReference) -> NSImage)?

    init(unreadOnOpen: Set<NotificationFeedEntry.ID> = []) {
        self.unreadOnOpen = unreadOnOpen
    }

    func noteCleared() { cleared = true }

    /// Moves the selection through `entries` by `offset`, starting at the top.
    func select(by offset: Int, in entries: [NotificationFeedEntry]) {
        guard !entries.isEmpty else { selection = nil; return }
        guard let current = selection, let index = entries.firstIndex(where: { $0.id == current }) else {
            selection = offset >= 0 ? entries.first?.id : entries.last?.id
            return
        }
        selection = entries[min(max(index + offset, 0), entries.count - 1)].id
    }

    /// Keeps the selection on a neighbor after its entry goes away.
    func repairSelection(in entries: [NotificationFeedEntry], removedIndex: Int?) {
        guard let current = selection, !entries.contains(where: { $0.id == current }) else { return }
        guard !entries.isEmpty else { selection = nil; return }
        selection = entries[min(removedIndex ?? 0, entries.count - 1)].id
    }
}
