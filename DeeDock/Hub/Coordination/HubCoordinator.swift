import AppKit
import Quartz
import SwiftUI

/// Where an anchored Hub opens: the display's identity, its DOKK tile, and the per-display inputs
/// the Apps tab needs.
struct HubOpenContext {
    /// Stable display identity, never a screen-array index.
    let displayID: String
    let anchor: HubAnchor
    let apps: HubAppsDisplayContext
}

/// The one DOKK Hub for the whole app: its three tab models, its window, what it remembers, and
/// every way into it (tile, Focus Dock, file drop, Open in Hub).
///
/// Only one Hub exists. It opens on the display whose tile, Focus Dock, or drop opened it, and
/// moves there when opened from another display. The dock coordinator owns this object for the
/// app's lifetime and supplies ``resolveContext`` and the other hooks.
///
/// Tab models hear about visibility only from here: ``HubTabModel/hubTabDidAppear(shell:)`` when a
/// tab becomes visible in an open Hub (on open or switch) and ``HubTabModel/hubTabDidDisappear()``
/// when it is hidden or the Hub closes. Calls always come in pairs.
@MainActor @Observable
final class HubCoordinator {
    let state: HubShellState
    let tile = HubTileState()
    let apps: HubAppsModel
    let windows: HubWindowsModel
    let files: HubFilesModel

    /// Returns where to open for a display, or for the display under the pointer when nil.
    @ObservationIgnored var resolveContext: ((String?) -> HubOpenContext?)?
    /// Runs before the Hub opens, so the dock can close popovers, Window Peek, and Focus Dock.
    /// Returns the app to reactivate when the Hub closes with Escape or its close button.
    @ObservationIgnored var willOpen: (() -> NSRunningApplication?)?
    /// Whether a mouse-down in another DOKK window landed on a DOKK tile. Such a click closes an
    /// anchored Hub and is consumed, so the tile does not reopen it.
    @ObservationIgnored var isTileClick: ((NSEvent) -> Bool)?
    /// Keeps the dock on `displayID` revealed while an anchored Hub points at it.
    @ObservationIgnored var holdDock: ((String, Bool) -> Void)?

    @ObservationIgnored private var panel: HubPanelController?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var preferences: HubShellPreferences
    @ObservationIgnored private var holds: [HubHoldReason: Int] = [:]
    /// The display the Hub opened on, while it is open.
    @ObservationIgnored private var displayID: String?
    /// The display whose dock is held revealed, while anchored.
    @ObservationIgnored private var heldDisplayID: String?
    @ObservationIgnored private var previousApplication: NSRunningApplication?
    /// The tab whose model has been told it appeared, so appear and disappear always pair up.
    @ObservationIgnored private var visibleTab: HubTab?

    /// - Parameters:
    ///   - launcher: The app-wide launcher state, already wired by the owner (search dispatch,
    ///     file actions, suggestions, capsules, tools).
    ///   - openRadar: Opens Radar from the Windows tab.
    init(launcher: LauncherState, openRadar: @escaping @MainActor () -> Void, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let preferences = HubShellPreferences.load(from: defaults)
        self.preferences = preferences
        state = HubShellState(tab: preferences.lastTab)
        apps = HubAppsModel(launcher: launcher)
        windows = HubWindowsModel(openRadar: openRadar)
        files = HubFilesModel(defaults: defaults)
        let files = files
        tile.transferProgress = { [weak files] in files?.transferProgress }
        let panel = HubPanelController(state: state, content: HubCoordinatorView(hub: self))
        self.panel = panel
        panel.keyDown = { [weak self] in self?.handleKeyDown($0) ?? false }
        panel.outsideClick = { [weak self] in self?.handleOutsideClick($0) ?? false }
        panel.resignedKey = { [weak self] in self?.handleResignKey() }
        panel.closeRequested = { [weak self] in self?.close(restoreFocus: true) }
        panel.detachedFrameChanged = { [weak self] frame in
            self?.preferences.detachedFrame = frame
            self?.savePreferences()
        }
    }

    /// True while the Hub is on screen.
    var isOpen: Bool { panel?.isVisible == true }

    /// The display the open Hub belongs to, or nil while closed.
    var openDisplayID: String? { isOpen ? displayID : nil }

    // MARK: - Entry points

    /// A DOKK tile click or Focus Dock's Return on the tile.
    ///
    /// Opens the Hub on `anchor`'s display on the last tab. A click while it is anchored closes
    /// it and reactivates the previous app. A click while it is detached brings the window
    /// forward and pulses the tile.
    func toggle(trigger: AnalyticsHubTrigger, anchor: HubOpenContext) {
        guard isOpen else {
            open(context: anchor, tab: preferences.lastTab, trigger: trigger)
            return
        }
        if state.isDetached {
            bringForward()
        } else if displayID != anchor.displayID {
            // A tile on another display moves the Hub there instead of closing it, so the
            // search text survives the hand-off.
            close(restoreFocus: false, animated: false, clearsSearch: false)
            open(context: anchor, tab: state.tab, trigger: trigger)
        } else {
            close(restoreFocus: true)
        }
    }

    /// Opens on `tab`, or switches to it when the Hub is already open. Opens on the display under
    /// the pointer.
    func open(tab: HubTab, trigger: AnalyticsHubTrigger) {
        if isOpen {
            selectTab(tab, via: nil)
            if state.isDetached { bringForward() } else { panel?.bringToFront() }
            return
        }
        guard let context = resolveContext?(nil) else { return }
        open(context: context, tab: tab, trigger: trigger)
    }

    /// Open in Hub from a folder stack, the Downloads stack, or a drive: shows `url` in Files.
    func openFolder(_ url: URL) {
        open(tab: .files, trigger: .openFolder)
        files.open(folder: url)
    }

    /// Files dropped on a DOKK tile or handed over from the Shelf: Apps tab, file-action mode.
    ///
    /// - Parameter context: The display whose tile received the drop; nil uses the pointer's.
    func adoptFiles(_ adoption: LauncherFileAdoption, on context: HubOpenContext? = nil) {
        if !isOpen, let context {
            open(context: context, tab: .apps, trigger: .fileDrop)
        } else {
            open(tab: .apps, trigger: .fileDrop)
        }
        apps.adoptFiles(adoption)
    }

    /// Closes the Hub without reactivating the previous app, as other DOKK surfaces opening do.
    func close() { close(restoreFocus: false) }

    /// Closes an anchored Hub when another dock surface (a stack, Focus Dock, Radar) takes over.
    /// A detached Hub is a window and stays; so does an anchored one with a hold or a running
    /// transfer, for example while a drag from the Files tab spring-loads a folder stack.
    func dismissAnchored() {
        guard isOpen, canDismissAnchored else { return }
        close(restoreFocus: false, animated: false)
    }

    /// Re-aims an anchored Hub after the dock moved, resized, or scrolled, and closes it when its
    /// display or tile is gone.
    func refreshAnchor() {
        guard isOpen, !state.isDetached, let displayID else { return }
        guard let context = resolveContext?(displayID) else {
            close(restoreFocus: false, animated: false)
            return
        }
        panel?.reanchor(HubGeometry.anchoredPlacement(anchor: context.anchor))
    }

    /// Sleep or display reconfiguration: an anchored Hub closes at once, whatever holds it, because
    /// its tile may no longer be where it points.
    func suspend() {
        guard isOpen, !state.isDetached else { return }
        close(restoreFocus: false, animated: false)
    }

    /// Ends the Hub for app teardown. Cancels running copies and moves so their partial
    /// destination items are removed before the process exits.
    func stop() {
        files.transfers.cancelAllForTermination()
        if isOpen { close(restoreFocus: false, animated: false) }
        panel?.stop()
        panel = nil
        resolveContext = nil; willOpen = nil; isTileClick = nil; holdDock = nil
    }

    // MARK: - Open and close

    private func open(context: HubOpenContext, tab: HubTab, trigger: AnalyticsHubTrigger) {
        guard let panel, !isOpen else { return }
        let previous = willOpen?() ?? NSWorkspace.shared.frontmostApplication
        previousApplication = previous?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : previous
        displayID = context.displayID
        holds = [:]
        apps.present(on: context.apps)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { state.select(tab) }
        if preferences.detached {
            let visible = NSScreen.screens.map(\.visibleFrame)
            let frame = preferences.detachedFrame.map {
                HubGeometry.restoredDetachedFrame($0, visibleFrames: visible, fallback: context.anchor.visibleFrame)
            } ?? HubGeometry.initialDetachedFrame(
                from: HubGeometry.anchoredPlacement(anchor: context.anchor).body,
                visibleFrame: context.anchor.visibleFrame)
            panel.showDetached(frame)
        } else {
            panel.showAnchored(HubGeometry.anchoredPlacement(anchor: context.anchor))
            setDockHold(context.displayID)
        }
        tile.setOpen(true)
        showVisibleTab()
        focusForCurrentTab()
        Analytics.track(.hubOpened(trigger: trigger, tab: state.tab, detached: state.isDetached))
    }

    /// - Parameters:
    ///   - restoreFocus: Reactivates the app that was frontmost before the Hub opened.
    ///   - animated: False skips the close animation, for display changes and hand-offs.
    ///   - clearsSearch: Empties every tab's search text. True for every real close, anchored or
    ///     detached; only moving the Hub to another display keeps it.
    private func close(restoreFocus: Bool, animated: Bool = true, clearsSearch: Bool = true) {
        guard let panel, isOpen else { return }
        hideVisibleTab()
        // Cleared after the visible tab hid, so Files leaves search mode without reactivating its
        // panes and Apps ends its session before its query resets.
        if clearsSearch { clearSearchText() }
        preferences.lastTab = state.tab
        preferences.detached = state.isDetached
        if let frame = panel.detachedFrame { preferences.detachedFrame = frame }
        savePreferences()
        holds = [:]
        setDockHold(nil)
        tile.setOpen(false)
        displayID = nil
        let previous = previousApplication
        previousApplication = nil
        if animated { panel.close() } else { panel.closeImmediately() }
        if restoreFocus, NSApp.isActive, let previous, !previous.isTerminated {
            previous.activate(options: [])
        }
    }

    /// Search text does not survive closing: Apps (via `LauncherState`), Windows, and Files all
    /// start empty next time. Files returns from search results to its panes.
    private func clearSearchText() {
        for tab in HubTab.allCases {
            let tabModel = model(for: tab)
            if !tabModel.query.isEmpty { tabModel.query = "" }
        }
    }

    private func bringForward() {
        panel?.bringToFront()
        tile.playPulse()
    }

    // MARK: - Tabs

    /// Switches tabs, telling the old model it disappeared and the new one it appeared.
    ///
    /// - Parameter via: How the person switched, for analytics; nil for a switch a tab requested.
    func selectTab(_ tab: HubTab, via: AnalyticsHubTabSwitch?) {
        guard tab != state.tab else { return }
        hideVisibleTab()
        withAnimation(state.reduceMotion ? nil : HubStyle.motion) { state.select(tab) }
        if isOpen { showVisibleTab() }
        preferences.lastTab = tab
        savePreferences()
        focusForCurrentTab()
        if let via { Analytics.track(.hubTabSelected(tab, via: via)) }
    }

    /// The model behind `tab`.
    func model(for tab: HubTab) -> any HubTabModel {
        switch tab {
        case .apps: apps
        case .windows: windows
        case .files: files
        }
    }

    private func showVisibleTab() {
        guard visibleTab == nil else { return }
        visibleTab = state.tab
        model(for: state.tab).hubTabDidAppear(shell: self)
    }

    private func hideVisibleTab() {
        guard let tab = visibleTab else { return }
        visibleTab = nil
        model(for: tab).hubTabDidDisappear()
    }

    /// Files opens with focus in its listing, the other tabs in the search field, as in the mockup.
    private func focusForCurrentTab() {
        if state.tab == .files { state.requestContentFocus() } else { state.requestSearchFocus() }
    }

    // MARK: - Detach

    /// The pin button: morphs between the anchored panel and a detached window.
    func togglePin() {
        guard let panel, isOpen else { return }
        if state.isDetached {
            let context = displayID.flatMap { resolveContext?($0) } ?? resolveContext?(nil)
            guard let context else { return }
            displayID = context.displayID
            panel.attach(to: HubGeometry.anchoredPlacement(anchor: context.anchor))
            setDockHold(context.displayID)
            preferences.detached = false
        } else {
            let body = panel.anchoredPlacement?.body ?? panel.window.frame
            let visible = panel.window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? body
            let frame = preferences.detachedFrame.map {
                HubGeometry.restoredDetachedFrame($0, visibleFrames: NSScreen.screens.map(\.visibleFrame), fallback: visible)
            } ?? HubGeometry.initialDetachedFrame(from: body, visibleFrame: visible)
            panel.detach(to: frame)
            setDockHold(nil)
            preferences.detached = true
            preferences.detachedFrame = frame
        }
        savePreferences()
        Analytics.track(.hubDetachChanged(detached: state.isDetached))
    }

    // MARK: - Dismissal

    /// Whether outside clicks, focus loss, and Escape may close an anchored Hub right now.
    private var canDismissAnchored: Bool {
        !state.isDetached && holds.values.allSatisfy { $0 <= 0 } && files.transferProgress == nil
    }

    private func handleOutsideClick(_ event: NSEvent?) -> Bool {
        guard isOpen, canDismissAnchored else { return false }
        if let event, event.window is DockPanel, isTileClick?(event) == true {
            // The tile toggles: this click closes the Hub and must not reach the tile to reopen it.
            close(restoreFocus: true)
            return true
        }
        close(restoreFocus: false)
        return false
    }

    private func handleResignKey() {
        guard isOpen, !state.isDetached else { return }
        // Decide once AppKit has settled the new key window: a sheet, Quick Look, or a menu
        // owned by the Hub takes key status without the Hub losing its place.
        DispatchQueue.main.async { [weak self] in
            guard let self, isOpen, canDismissAnchored, let panel else { return }
            if panel.window.isKeyWindow { return }
            if let key = NSApp.keyWindow {
                if key.level == .popUpMenu || key is QLPreviewPanel
                    || key.sheetParent === panel.window || key.parent === panel.window { return }
            }
            close(restoreFocus: false)
        }
    }

    // MARK: - Keyboard

    /// Offers the event to the visible tab first, then handles ⌘1–⌘3, ⌘F, ⌘W, and Escape.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let editor = panel?.window.firstResponder as? NSTextView
        if editor?.hasMarkedText() == true { return false }
        let fromSearchField = editor != nil && state.searchFieldFocused
        if model(for: state.tab).handleKeyDown(event, fromSearchField: fromSearchField) { return true }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command, let key, let tab = HubTab.allCases.first(where: { String($0.shortcutDigit) == key }) {
            selectTab(tab, via: .keyboard)
            return true
        }
        if modifiers == .command, key == "f" {
            if panel?.window.isKeyWindow == false { panel?.bringToFront() }
            state.requestSearchFocus()
            return true
        }
        if modifiers == .command, key == "w" {
            close(restoreFocus: true)
            return true
        }
        guard event.keyCode == 53, modifiers.isEmpty else { return false }
        let tabModel = model(for: state.tab)
        if !tabModel.query.isEmpty {
            tabModel.query = ""
            return true
        }
        // A detached Hub is a window: Escape only clears the search.
        if canDismissAnchored { close(restoreFocus: true) }
        return true
    }

    // MARK: - Holds and persistence

    private func setDockHold(_ displayID: String?) {
        if let heldDisplayID, heldDisplayID != displayID { holdDock?(heldDisplayID, false) }
        if let displayID, displayID != heldDisplayID { holdDock?(displayID, true) }
        heldDisplayID = displayID
    }

    private func savePreferences() { preferences.save(to: defaults) }

    /// Header actions for the root view.
    var headerActions: HubHeaderActions {
        HubHeaderActions(select: { [weak self] in self?.selectTab($0, via: .click) },
                         togglePin: { [weak self] in self?.togglePin() },
                         close: { [weak self] in self?.close(restoreFocus: true) })
    }
}

// MARK: - HubShell

extension HubCoordinator: HubShell {
    var isDetached: Bool { state.isDetached }

    func dismissAfterAction() {
        guard !state.isDetached else { return }
        close(restoreFocus: false)
    }

    func beginHold(_ reason: HubHoldReason) {
        holds[reason, default: 0] += 1
    }

    func endHold(_ reason: HubHoldReason) {
        guard let count = holds[reason], count > 0 else { return }
        holds[reason] = count - 1
    }

    func select(_ tab: HubTab) { selectTab(tab, via: nil) }

    func focusSearchField() {
        if panel?.window.isKeyWindow == false { panel?.bringToFront() }
        // Tabs call this when typing in their content moves into search; keep the typed text intact.
        state.requestSearchFocus(caretAtEnd: true)
    }

    func focusContent() {
        state.requestContentFocus()
        if let window = panel?.window, window.firstResponder is NSTextView {
            window.makeFirstResponder(window.contentView)
        }
    }
}

/// Binds the root view to the coordinator: the header search follows the visible tab's model.
private struct HubCoordinatorView: View {
    let hub: HubCoordinator

    var body: some View {
        let model = hub.model(for: hub.state.tab)
        HubRootView(state: hub.state,
                    query: Binding(get: { model.query }, set: { model.query = $0 }),
                    prompt: model.searchPrompt,
                    actions: hub.headerActions) { tab in
            HubTabView(hub: hub, tab: tab)
        }
    }
}

/// One tab's content view.
private struct HubTabView: View {
    let hub: HubCoordinator
    let tab: HubTab

    var body: some View {
        switch tab {
        case .apps: HubAppsView(model: hub.apps)
        case .windows: HubWindowsView(model: hub.windows)
        case .files: HubFilesView(model: hub.files)
        }
    }
}
