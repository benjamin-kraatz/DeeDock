import AppKit
import Observation

/// Presentation state for one open notification feed popover.
///
/// The entries themselves stay in ``NotificationFeedStore``; this holds only what belongs to the
/// open panel: its chrome, keyboard selection, which stacks are unfolded, how leaving entries
/// animate, the swipe gesture, which entries were new when it opened, and the commands the
/// coordinator handles.
@MainActor @Observable
final class NotificationFeedPanelState {
    var chrome = DockPopoverChrome(edge: .bottom, attachment: 190)
    /// The keyboard selection: an item's identifier, which is a folded stack's front entry.
    /// Nil until the person presses an arrow key or clicks a stack.
    var selection: NotificationFeedEntry.ID?
    /// Identifiers of the groups the person unfolded.
    private(set) var expanded: Set<String> = []
    /// How entries about to leave animate. Staged a frame before they leave; see
    /// ``NotificationFeedLeaveStyle``.
    private(set) var leaving: [NotificationFeedEntry.ID: NotificationFeedLeaveStyle] = [:]
    /// Entries that were unread when the panel opened. They keep their marker while it stays open.
    let unreadOnOpen: Set<NotificationFeedEntry.ID>
    /// Owns the scroll-wheel monitor; started and stopped with the popover.
    let swipe = NotificationFeedSwipeTracker()
    /// Set when the person cleared the feed while this panel was open. Reported on close.
    private(set) var cleared = false

    /// Brings the entry's app forward. The ambient analytics trigger says how.
    @ObservationIgnored var open: ((NotificationFeedEntry) -> Void)?
    @ObservationIgnored var copy: ((NotificationFeedEntry) -> Void)?
    @ObservationIgnored var remove: ((NotificationFeedEntry.ID, AnalyticsNotificationFeedRemoval) -> Void)?
    /// Clears a whole sender's stack, folding it first when it is unfolded.
    @ObservationIgnored var clearGroup: ((NotificationFeedGroup, AnalyticsNotificationFeedRemoval) -> Void)?
    /// The header's Clear All.
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

    // MARK: - Groups

    /// The selectable items for `entries`, in display order.
    func items(in entries: [NotificationFeedEntry]) -> [NotificationFeedItem] {
        NotificationFeedGrouping.items(NotificationFeedGrouping.groups(entries), expanded: expanded)
    }

    func isExpanded(_ group: NotificationFeedGroup) -> Bool {
        group.isStack && expanded.contains(group.id)
    }

    /// Unfolds or folds a stack. Folding moves a selection inside it to the front card, which is
    /// the only part of the stack that can then be selected.
    func setExpanded(_ group: NotificationFeedGroup, _ isExpanded: Bool) {
        if isExpanded {
            guard group.isStack else { return }
            expanded.insert(group.id)
        } else {
            expanded.remove(group.id)
            if let selection, group.entries.dropFirst().contains(where: { $0.id == selection }) {
                self.selection = group.front.id
            }
        }
    }

    /// Forgets unfolded groups that are gone or down to one entry, so a sender that posts again
    /// later starts folded.
    func pruneExpanded(in entries: [NotificationFeedEntry]) {
        let stacks = Set(NotificationFeedGrouping.groups(entries).filter(\.isStack).map(\.id))
        let kept = expanded.intersection(stacks)
        if kept != expanded { expanded = kept }
    }

    func collapseAll() {
        if !expanded.isEmpty { expanded = [] }
    }

    // MARK: - Leaving

    /// The transition style for an entry or a group whose front is `id`.
    func leaveStyle(for id: NotificationFeedEntry.ID) -> NotificationFeedLeaveStyle {
        leaving[id] ?? .shrink
    }

    func stage(_ style: NotificationFeedLeaveStyle, for ids: Set<NotificationFeedEntry.ID>) {
        for id in ids { leaving[id] = style }
    }

    func unstage(_ ids: Set<NotificationFeedEntry.ID>) {
        for id in ids { leaving[id] = nil }
    }

    // MARK: - Selection

    /// Moves the selection through `items` by `offset`, starting at the top.
    func select(by offset: Int, in items: [NotificationFeedItem]) {
        guard !items.isEmpty else { selection = nil; return }
        guard let current = selection, let index = items.firstIndex(where: { $0.id == current }) else {
            selection = offset >= 0 ? items.first?.id : items.last?.id
            return
        }
        selection = items[min(max(index + offset, 0), items.count - 1)].id
    }

    /// Keeps the selection on a neighbor after its item goes away.
    func repairSelection(in items: [NotificationFeedItem], removedIndex: Int?) {
        guard let current = selection, !items.contains(where: { $0.id == current }) else { return }
        guard !items.isEmpty else { selection = nil; return }
        selection = items[min(removedIndex ?? 0, items.count - 1)].id
    }
}
