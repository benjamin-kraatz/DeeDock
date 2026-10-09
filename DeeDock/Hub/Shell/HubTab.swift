import AppKit

/// The Hub's top-level tabs, in switcher order (⌘1, ⌘2, ⌘3).
enum HubTab: String, CaseIterable, Codable, Sendable, Identifiable {
    case apps
    case windows
    case files

    var id: Self { self }
}

/// Why an anchored Hub must stay open through an outside click or loss of key status.
///
/// Holds are counted per reason, so nested begin/end pairs from independent owners compose.
enum HubHoldReason: Hashable, Sendable {
    /// A drag session that started in the Hub is in flight, possibly over another app.
    case drag
    /// A modal sheet, open panel, or alert owned by the Hub is showing.
    case modal
    /// A context menu opened from Hub content is tracking.
    case menu
}

/// Services the Hub shell offers to its tabs.
///
/// One shell exists per app; it owns the panel, the header (tab switcher and search field), and
/// dismissal. All members are main-actor isolated.
@MainActor
protocol HubShell: AnyObject {
    /// True while the Hub is a normal, movable window rather than a panel anchored to its dock tile.
    var isDetached: Bool { get }

    /// Closes an anchored Hub after an action handed focus elsewhere (launching an app, activating a
    /// window, opening a document). A detached Hub stays open, like a Finder window.
    func dismissAfterAction()

    /// Closes the Hub regardless of mode.
    func close()

    /// Keeps an anchored Hub open across outside clicks and focus loss until `endHold(_:)` is called
    /// with the same reason the same number of times.
    func beginHold(_ reason: HubHoldReason)

    /// Releases one hold taken with `beginHold(_:)`.
    func endHold(_ reason: HubHoldReason)

    /// Switches the visible tab with the same transition as the switcher.
    func select(_ tab: HubTab)

    /// Moves keyboard focus to the header search field.
    func focusSearchField()

    /// Gives keyboard focus back to the tab's content (after the search field ends editing).
    func focusContent()
}

/// A tab's model as seen by the shell.
///
/// The shell binds its header search field to `query` while the tab is visible, forwards key
/// events, and reports visibility so tabs can start and stop discovery and file-system monitors.
@MainActor
protocol HubTabModel: AnyObject {
    /// Text in the header search field for this tab. Each tab keeps its own query.
    var query: String { get set }

    /// Placeholder for the header search field while this tab is visible.
    var searchPrompt: LocalizedStringResource { get }

    /// The tab became visible in an open Hub. Start discovery or monitors here; `shell` stays valid
    /// until the matching `hubTabDidDisappear()`.
    func hubTabDidAppear(shell: HubShell)

    /// The tab was hidden or the Hub closed. Cancel discovery and stop monitors here.
    func hubTabDidDisappear()

    /// A key-down event while the Hub is key and this tab is visible.
    ///
    /// The shell offers every event to the tab first, including those typed into the header search
    /// field (arrows, Return, Tab). It handles ⌘1–⌘3, ⌘F, and Escape itself only when this returns
    /// `false`. Escape falls back to clearing `query`, then to closing an anchored Hub.
    /// - Returns: `true` when the tab consumed the event.
    func handleKeyDown(_ event: NSEvent, fromSearchField: Bool) -> Bool
}
