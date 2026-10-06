import AppKit

/// App-wide owner for the single notification feed popover.
///
/// The feed is shared, so the popover opens from any display's tile and always shows the same
/// entries. Only one dock popover is open at a time, arbitrated by ``DockPopoverPresenter``.
/// Opening marks every entry read. Analytics receive counts only: how many entries the feed held
/// at open and close, how many were unread, and whether it was cleared. Never text or app names.
@MainActor
final class NotificationFeedCoordinator {
    private let feed: NotificationFeedController
    private let presenter: DockPopoverPresenter
    private let catalog: ApplicationCatalog
    private var controller: DockPopoverPanelController<NotificationFeedPanel>?
    private var state: NotificationFeedPanelState?
    private var resolver: NotificationFeedAppResolver?
    private weak var source: DockPanelController?
    private var openedAt: Date?
    var keyboardDismissed: ((String) -> Void)?
    /// Routes the next Settings window to the notification feed page.
    var prepareSettings: (() -> Void)?
    var isOpen: Bool { controller != nil }

    init(feed: NotificationFeedController, presenter: DockPopoverPresenter, catalog: ApplicationCatalog) {
        self.feed = feed
        self.presenter = presenter
        self.catalog = catalog
        presenter.register(.notificationFeed) { [weak self] in self?.close() }
    }

    func toggle(on panel: DockPanelController, keyboard: Bool) {
        if source === panel, controller != nil { close(returnFocus: keyboard); return }
        close()
        presenter.prepareToOpen(.notificationFeed)
        guard let anchor = panel.popoverAnchor(for: .notificationFeed) else { return }

        let store = feed.store
        let unreadCount = store.unreadCount
        let state = NotificationFeedPanelState(unreadOnOpen: Set(store.entries.prefix(unreadCount).map(\.id)))
        let resolver = NotificationFeedAppResolver(
            running: { [catalog] in catalog.running },
            installed: { [catalog] in catalog.launcherLibrary.applications.map(\.reference) })
        state.application = { [resolver] in resolver.application(named: $0.appName) }
        state.icon = { [resolver] in resolver.icon(for: $0) }
        state.open = { [weak self] in self?.open($0) }
        state.copy = { Self.copy($0) }
        state.remove = { [weak self] in self?.remove($0) }
        state.clearAll = { [weak self] in self?.clear() }
        state.prepareSettings = { [weak self] in
            self?.prepareSettings?()
            self?.close()
        }

        let next = DockPopoverPanelController(anchor: anchor, keyboard: keyboard, clickFocus: true,
                                              ideal: CGSize(width: 380, height: 480)) { chrome in
            state.chrome = chrome
        } content: {
            NotificationFeedPanel(feed: feed, state: state)
        }
        self.state = state
        self.resolver = resolver
        controller = next
        source = panel
        openedAt = .now
        store.isViewing = true
        panel.holdPopover(true)
        presenter.didOpen(.notificationFeed)

        next.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        next.closed = { [weak self, weak panel] returnFocus in
            guard let self else { return }
            let sourceID = panel?.store.displayID
            reportClose()
            feed.store.isViewing = false
            panel?.holdPopover(false)
            presenter.didClose(.notificationFeed)
            controller = nil; self.state = nil; self.resolver = nil; source = nil; openedAt = nil
            if returnFocus { panel?.focus() }
            else if keyboard, let sourceID { keyboardDismissed?(sourceID) }
        }
        next.show()
        Analytics.track(.notificationFeedOpened(entryCount: store.entries.count, unreadCount: unreadCount,
                                                trigger: Analytics.trigger(keyboard: keyboard)))
    }

    /// Empties the feed from the tile's menu or the popover's Clear button.
    func clear() {
        guard !feed.store.isEmpty else { return }
        state?.noteCleared()
        feed.store.clear()
        state?.selection = nil
    }

    func reanchor() {
        guard controller != nil else { return }
        guard let source, let anchor = source.popoverAnchor(for: .notificationFeed) else { close(); return }
        controller?.update(anchor)
    }

    func close(for displayID: String? = nil, returnFocus: Bool = false) {
        guard displayID == nil || source?.store.displayID == displayID else { return }
        controller?.close(returnFocus: returnFocus)
    }

    func stop() { close(); keyboardDismissed = nil; prepareSettings = nil }

    // MARK: - Commands

    /// Brings the sending app forward when its name resolves to exactly one application.
    /// The notification itself cannot be reopened: its banner is gone.
    private func open(_ entry: NotificationFeedEntry) {
        guard let reference = resolver?.application(named: entry.appName) else { return }
        close()
        catalog.open(reference) { [weak self] error in
            if let error { self?.source?.store.errorMessage = error }
        }
    }

    private func remove(_ id: NotificationFeedEntry.ID) {
        let index = feed.store.entries.firstIndex { $0.id == id }
        feed.store.remove(id)
        state?.repairSelection(in: feed.store.entries, removedIndex: index)
    }

    /// Copies what the banner said, for a code or an address the person needs elsewhere.
    private static func copy(_ entry: NotificationFeedEntry) {
        let text = [entry.title, entry.subtitle, entry.body].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func reportClose() {
        guard let openedAt else { return }
        Analytics.track(.notificationFeedClosed(entryCount: feed.store.entries.count,
                                                duration: Date.now.timeIntervalSince(openedAt),
                                                cleared: state?.cleared ?? false))
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let state else { return false }
        let entries = feed.store.entries
        if event.modifierFlags.contains(.command) {
            switch (event.charactersIgnoringModifiers, event.keyCode) {
            case ("c", _):
                guard let entry = selectedEntry(state, in: entries) else { return false }
                state.copy?(entry)
                return true
            case (_, 51), (_, 117):
                clear()
                return true
            default:
                return false
            }
        }
        switch event.keyCode {
        case 53:
            close(returnFocus: source?.store.keyboardFocus == true)
        case 125:
            state.select(by: 1, in: entries)
        case 126:
            state.select(by: -1, in: entries)
        case 36, 76:
            guard let entry = selectedEntry(state, in: entries) else { return false }
            open(entry)
        case 51, 117:
            guard let id = state.selection else { return false }
            remove(id)
        default:
            return false
        }
        return true
    }

    private func selectedEntry(_ state: NotificationFeedPanelState, in entries: [NotificationFeedEntry]) -> NotificationFeedEntry? {
        guard let id = state.selection else { return nil }
        return entries.first { $0.id == id }
    }
}
