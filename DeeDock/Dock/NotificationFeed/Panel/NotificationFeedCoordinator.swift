import AppKit
import SwiftUI

/// App-wide owner for the single notification feed popover, and for the feed's triage rules.
///
/// The feed is shared, so the popover opens from any display's tile and always shows the same
/// entries. Only one dock popover is open at a time, arbitrated by ``DockPopoverPresenter``.
/// Opening marks every entry read.
///
/// Triage (DEE-155):
/// - Bringing an app forward, from the feed or anywhere else, removes its entries. The sender is
///   matched with the same exact-name resolution as Open App, never guessed, and system alerts
///   are never cleared this way. ``applicationActivated(_:)`` receives every activation.
/// - With **Clear when closed** on, closing the feed removes what was shown while it was open.
///
/// Analytics receive counts and closed vocabularies only: never text, app names, or bundle
/// identifiers, and nothing when a notification arrives.
@MainActor
final class NotificationFeedCoordinator {
    private let feed: NotificationFeedController
    private let presenter: DockPopoverPresenter
    private let catalog: ApplicationCatalog
    /// Shared by the popover and activation matching, so both resolve a name the same way.
    private let resolver: NotificationFeedAppResolver
    private var controller: DockPopoverPanelController<NotificationFeedPanel>?
    private var state: NotificationFeedPanelState?
    private weak var source: DockPanelController?
    private var openedAt: Date?
    /// Removals staged on the open panel and finished a frame later. Flushed when it closes.
    private var pendingRemovals: [UUID: PendingRemoval] = [:]
    /// Closes the popover once an opened entry has dropped. Cancelled by any other close.
    private var pendingClose: Task<Void, Never>?
    /// A Clear-when-closed waiting for the popover's close animation. Run at once if the feed
    /// reopens first.
    private var pendingSeenClear: Task<Void, Never>?
    var keyboardDismissed: ((String) -> Void)?
    /// Routes the next Settings window to the notification feed page.
    var prepareSettings: (() -> Void)?
    /// Mirrors the **Clear when closed** setting. Set by the dock coordinator.
    var clearsOnClose = false
    var isOpen: Bool { controller != nil }

    private struct PendingRemoval {
        let ids: Set<NotificationFeedEntry.ID>
        let task: Task<Void, Never>
    }

    init(feed: NotificationFeedController, presenter: DockPopoverPresenter, catalog: ApplicationCatalog) {
        self.feed = feed
        self.presenter = presenter
        self.catalog = catalog
        resolver = NotificationFeedAppResolver(
            running: { [catalog] in catalog.running },
            installed: { [catalog] in catalog.launcherLibrary.applications.map(\.reference) })
        presenter.register(.notificationFeed) { [weak self] in self?.close() }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var motion: Animation? { NotificationFeedMotion.layout(reduceMotion: reduceMotion) }

    func toggle(on panel: DockPanelController, keyboard: Bool) {
        if source === panel, controller != nil { close(returnFocus: keyboard); return }
        close()
        presenter.prepareToOpen(.notificationFeed)
        guard let anchor = panel.popoverAnchor(for: .notificationFeed) else { return }

        // A Clear-when-closed still waiting on the last close animation applies before anything
        // is counted, so the reopened feed never shows what it was about to drop.
        flushSeenClear()
        let store = feed.store
        let unreadCount = store.unreadCount
        let state = NotificationFeedPanelState(unreadOnOpen: Set(store.entries.prefix(unreadCount).map(\.id)))
        resolver.invalidate()
        state.application = { [resolver] in resolver.application(named: $0.appName) }
        state.icon = { [resolver] in resolver.icon(for: $0) }
        state.open = { [weak self] in self?.open($0, trigger: Analytics.trigger()) }
        state.copy = { Self.copy($0) }
        state.remove = { [weak self] in self?.removeEntry($0, method: $1) }
        state.clearGroup = { [weak self] in self?.clearGroup($0.id, method: $1) }
        state.clearAll = { [weak self] in self?.clear(source: .header) }
        state.prepareSettings = { [weak self] in
            self?.prepareSettings?()
            self?.close()
        }
        state.swipe.onCommit = { [weak self] id, isStack in self?.swiped(id, isStack: isStack) }

        let next = DockPopoverPanelController(anchor: anchor, keyboard: keyboard, clickFocus: true,
                                              ideal: CGSize(width: 380, height: 480)) { chrome in
            state.chrome = chrome
        } content: {
            NotificationFeedPanel(feed: feed, state: state)
        }
        self.state = state
        controller = next
        source = panel
        openedAt = .now
        store.isViewing = true
        panel.holdPopover(true)
        presenter.didOpen(.notificationFeed)
        state.swipe.start()

        next.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        next.closed = { [weak self, weak panel] returnFocus in
            guard let self else { return }
            let sourceID = panel?.store.displayID
            reportClose()
            pendingClose?.cancel()
            pendingClose = nil
            flushRemovals()
            state.swipe.stop()
            feed.store.isViewing = false
            if clearsOnClose { scheduleSeenClear() }
            panel?.holdPopover(false)
            presenter.didClose(.notificationFeed)
            controller = nil; self.state = nil; source = nil; openedAt = nil
            if returnFocus { panel?.focus() }
            else if keyboard, let sourceID { keyboardDismissed?(sourceID) }
        }
        next.show()
        Analytics.track(.notificationFeedOpened(entryCount: store.entries.count, unreadCount: unreadCount,
                                                trigger: Analytics.trigger(keyboard: keyboard)))
    }

    /// Empties the feed from the tile's menu or its VoiceOver action. The ambient analytics
    /// trigger tells the two apart.
    func clearFromTile() {
        clear(source: Analytics.trigger() == .voiceOver ? .voiceOver : .tileMenu)
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

    func stop() {
        close()
        flushSeenClear()
        keyboardDismissed = nil
        prepareSettings = nil
    }

    // MARK: - Auto-clear

    /// Removes the entries of an application that came to the front.
    ///
    /// Called for every activation except DOKK's own. Only names that resolve to exactly this
    /// application match. With the feed open the entries drop toward the dock; with it closed
    /// only the tile's badge changes.
    func applicationActivated(_ application: NSRunningApplication) {
        guard !feed.store.isEmpty, let applicationID = NotificationFeedAutoClear.applicationID(of: application) else { return }
        // An app launched since the last lookup may now be the only match for its name.
        resolver.invalidate()
        let ids = Set(NotificationFeedAutoClear.entryIDs(in: feed.store.entries, applicationID: applicationID,
                                                         resolve: { resolver.application(named: $0) }))
            .subtracting(pendingIDs)
        guard !ids.isEmpty else { return }
        removeAnimated(ids, style: .drop)
        Analytics.track(.notificationFeedAutoCleared(count: ids.count))
    }

    // MARK: - Commands

    /// Brings the sending app forward when its name resolves to exactly one application, and
    /// takes every entry from that app with it. The notification itself cannot be reopened: its
    /// banner is gone.
    ///
    /// The entries drop toward the dock while the app opens, then the popover closes, so the
    /// drop is visible before the panel fades. If the app fails to open, its entries are still
    /// gone and the dock shows the error.
    private func open(_ entry: NotificationFeedEntry, trigger: AnalyticsTrigger) {
        guard let reference = resolver.application(named: entry.appName) else { return }
        let ids = Set(NotificationFeedAutoClear.entryIDs(in: feed.store.entries, applicationID: reference.id,
                                                         resolve: { resolver.application(named: $0) }))
            .subtracting(pendingIDs)
        removeAnimated(ids, style: .drop)
        Analytics.track(.notificationFeedRowOpened(trigger: trigger, clearedCount: ids.count))
        catalog.open(reference) { [weak source] error in
            if let error { source?.store.errorMessage = error }
        }
        pendingClose?.cancel()
        let delay = NotificationFeedMotion.closeDelay(reduceMotion: reduceMotion)
        pendingClose = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    private func removeEntry(_ id: NotificationFeedEntry.ID, method: AnalyticsNotificationFeedRemoval) {
        guard feed.store.entries.contains(where: { $0.id == id }), !pendingIDs.contains(id) else { return }
        removeAnimated([id], style: method == .swipe ? .swiped : .shrink)
        Analytics.track(.notificationFeedRowRemoved(method: method))
    }

    /// Clears one sender's stack. An unfolded stack first folds its rows into the front card,
    /// then the card fades; a swiped stack has already flown out.
    private func clearGroup(_ groupID: String, method: AnalyticsNotificationFeedRemoval) {
        guard let group = NotificationFeedGrouping.groups(feed.store.entries).first(where: { $0.id == groupID }) else { return }
        let ids = Set(group.entries.map(\.id)).subtracting(pendingIDs)
        guard !ids.isEmpty else { return }
        var delay = Duration.zero
        if let state, state.isExpanded(group), method != .swipe {
            withAnimation(motion) { state.setExpanded(group, false) }
            delay = NotificationFeedMotion.foldDelay(reduceMotion: reduceMotion)
        }
        removeAnimated(ids, style: method == .swipe ? .swiped : .shrink, after: delay)
        Analytics.track(.notificationFeedGroupCleared(method: method, count: ids.count))
    }

    /// Empties the feed: header Clear All, Command-Delete, or the tile.
    private func clear(source: AnalyticsNotificationFeedClearSource) {
        guard !feed.store.isEmpty else { return }
        state?.noteCleared()
        // Everything goes, so staged removals have nothing left to do.
        for pending in pendingRemovals.values { pending.task.cancel() }
        pendingRemovals = [:]
        let count: Int
        if let state {
            count = withAnimation(motion) {
                state.collapseAll()
                state.selection = nil
                return feed.store.clear()
            }
        } else {
            count = feed.store.clear()
        }
        Analytics.track(.notificationFeedClearedAll(source: source, count: count))
    }

    /// A row or a whole stack has flown out under a swipe.
    private func swiped(_ id: NotificationFeedEntry.ID, isStack: Bool) {
        if isStack, let group = NotificationFeedGrouping.groups(feed.store.entries).first(where: { $0.front.id == id }) {
            clearGroup(group.id, method: .swipe)
        } else {
            removeEntry(id, method: .swipe)
        }
    }

    /// Copies what the banner said, for a code or an address the person needs elsewhere.
    private static func copy(_ entry: NotificationFeedEntry) {
        let text = [entry.title, entry.subtitle, entry.body].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Removal timing

    private var pendingIDs: Set<NotificationFeedEntry.ID> {
        pendingRemovals.values.reduce(into: []) { $0.formUnion($1.ids) }
    }

    /// Removes entries with the transition `style` asks for.
    ///
    /// SwiftUI takes a removed view's transition from its last rendered state, so the style is
    /// staged on the panel first and the store drops the entries a frame later. Without that the
    /// rows would leave with whatever style they last rendered. With the feed closed there is
    /// nothing to animate and the entries go at once.
    /// - Parameter delay: Extra time before the entries go, such as a stack folding first.
    private func removeAnimated(_ ids: Set<NotificationFeedEntry.ID>, style: NotificationFeedLeaveStyle,
                                after delay: Duration = .zero) {
        guard !ids.isEmpty else { return }
        guard let state else {
            feed.store.remove(ids)
            return
        }
        state.stage(style, for: ids)
        let token = UUID()
        let task = Task { [weak self] in
            // One frame at 60 Hz, plus a little, for the staged style to render.
            try? await Task.sleep(for: delay + .milliseconds(20))
            guard !Task.isCancelled else { return }
            self?.finishRemoval(token)
        }
        pendingRemovals[token] = PendingRemoval(ids: ids, task: task)
    }

    private func finishRemoval(_ token: UUID) {
        guard let pending = pendingRemovals.removeValue(forKey: token) else { return }
        guard let state else {
            feed.store.remove(pending.ids)
            return
        }
        let removedIndex = state.items(in: feed.store.entries).firstIndex { pending.ids.contains($0.id) }
        withAnimation(motion) {
            feed.store.remove(pending.ids)
            state.pruneExpanded(in: feed.store.entries)
        }
        state.repairSelection(in: state.items(in: feed.store.entries), removedIndex: removedIndex)
        state.unstage(pending.ids)
    }

    /// Finishes every staged removal at once, for a closing popover.
    private func flushRemovals() {
        let ids = pendingIDs
        for pending in pendingRemovals.values { pending.task.cancel() }
        pendingRemovals = [:]
        feed.store.remove(ids)
    }

    private func scheduleSeenClear() {
        pendingSeenClear?.cancel()
        // Reduce Motion closes the panel without animation, so there is nothing to wait for.
        guard !reduceMotion else { feed.store.clearSeen(); return }
        pendingSeenClear = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.pendingSeenClear = nil
            self?.feed.store.clearSeen()
        }
    }

    private func flushSeenClear() {
        guard let task = pendingSeenClear else { return }
        task.cancel()
        pendingSeenClear = nil
        feed.store.clearSeen()
    }

    private func reportClose() {
        guard let openedAt else { return }
        Analytics.track(.notificationFeedClosed(entryCount: feed.store.entries.count,
                                                duration: Date.now.timeIntervalSince(openedAt),
                                                cleared: state?.cleared ?? false))
    }

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let state else { return false }
        let items = state.items(in: feed.store.entries)
        let current = state.selection.flatMap { id in items.first { $0.id == id } }
        if event.modifierFlags.contains(.command) {
            switch (event.charactersIgnoringModifiers, event.keyCode) {
            case ("c", _):
                guard let current else { return false }
                state.copy?(current.entry)
                return true
            case (_, 51), (_, 117):
                clear(source: .keyboard)
                return true
            default:
                return false
            }
        }
        switch event.keyCode {
        case 53:
            if state.swipe.hasRevealed { state.swipe.closeRevealed() }
            else { close(returnFocus: source?.store.keyboardFocus == true) }
        case 125:
            state.select(by: 1, in: items)
        case 126:
            state.select(by: -1, in: items)
        case 124:
            guard let current, current.isCollapsedStack else { return false }
            withAnimation(motion) { state.setExpanded(current.group, true) }
        case 123:
            guard let current, current.isInExpandedGroup else { return false }
            withAnimation(motion) { state.setExpanded(current.group, false) }
        case 36, 76:
            guard let current else { return false }
            if current.isCollapsedStack {
                withAnimation(motion) { state.setExpanded(current.group, true) }
            } else {
                guard resolver.application(named: current.entry.appName) != nil else { return false }
                open(current.entry, trigger: .keyboard)
            }
        case 51, 117:
            guard let current else { return false }
            if current.isCollapsedStack { clearGroup(current.group.id, method: .keyboard) }
            else { removeEntry(current.id, method: .keyboard) }
        default:
            return false
        }
        return true
    }
}
