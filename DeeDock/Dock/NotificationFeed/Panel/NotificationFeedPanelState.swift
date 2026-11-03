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
    /// The latest request to scroll an item into view. Set only by keyboard navigation through
    /// ``revealSelection()``, never by a selection change itself: ``reconcile(from:to:)`` moves
    /// the selection silently when banners arrive, and following it would pull a person who
    /// scrolled away to read back to the selected row.
    private(set) var scrollRequest: NotificationFeedScrollRequest?
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

    /// Asks the panel to scroll the selected item into view. Called after keyboard navigation:
    /// the arrow keys, unfolding or folding a stack with ←, →, or Return. Each call issues a new
    /// request, so the same item can be revealed again after the person scrolled away.
    func revealSelection() {
        guard let selection else { return }
        scrollRequest = NotificationFeedScrollRequest(target: selection, sequence: (scrollRequest?.sequence ?? 0) + 1)
    }

    // MARK: - Reconciling

    /// Brings unfolded stacks and the selection in line with the feed after its entries changed,
    /// by an arrival, a cap eviction, or a removal.
    ///
    /// The selection is an item identifier, and a folded stack's item is its front entry, which
    /// changes when the sender posts again. Without this the selection would stay on the entry
    /// that slid behind the front card, and Return, →, Delete, and Command-C would act on nothing
    /// until the next arrow key.
    /// - A selected entry now hidden inside a folded stack moves to that stack's front.
    /// - A selected entry that left the feed moves to what survived of its folded stack, else to
    ///   its nearest surviving neighbor in the previous order: the next item, or the one before
    ///   when nothing after it survived. Positions are not used, because arrivals in the same
    ///   change shift them.
    /// - Unfolded groups that are gone or down to one entry are forgotten.
    func reconcile(from previous: [NotificationFeedEntry], to current: [NotificationFeedEntry]) {
        // Read before pruning, so the neighbors are the rows the person last saw.
        let previousItems = selection == nil ? [] : items(in: previous)
        pruneExpanded(in: current)
        guard let selected = selection else { return }
        let currentItems = items(in: current)
        let groups = NotificationFeedGrouping.groups(current)
        // The item that now shows an entry: its own row, or the front of the folded stack hiding it.
        func visibleItem(for id: NotificationFeedEntry.ID) -> NotificationFeedEntry.ID? {
            if currentItems.contains(where: { $0.id == id }) { return id }
            return groups.first { $0.entries.contains { $0.id == id } }?.front.id
        }
        if let visible = visibleItem(for: selected) {
            if visible != selected { selection = visible }
            return
        }
        guard let index = previousItems.firstIndex(where: { $0.id == selected }) else {
            selection = currentItems.first?.id
            return
        }
        let item = previousItems[index]
        let stackmates = item.isCollapsedStack ? item.group.entries.dropFirst().map(\.id) : []
        let neighbors = (previousItems[(index + 1)...] + previousItems[..<index].reversed()).map(\.id)
        selection = (stackmates + neighbors).lazy.compactMap(visibleItem(for:)).first ?? currentItems.first?.id
    }
}

/// A one-time request to scroll an item of the open feed into view.
///
/// The sequence number makes each request distinct, so revealing the same item twice still
/// scrolls the second time.
struct NotificationFeedScrollRequest: Equatable {
    /// The item to show: an entry, or a folded stack's front entry.
    let target: NotificationFeedEntry.ID
    let sequence: Int
}
