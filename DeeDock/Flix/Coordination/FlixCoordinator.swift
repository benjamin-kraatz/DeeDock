import AppKit
import Observation
import SwiftUI

/// Flix Files' owner, held by `DockCoordinator` for the app's lifetime.
///
/// It owns the history, the settings, the intelligence slots, the shared tile state, the sources,
/// the shortcut, the menu bar item, and the one panel. `DockCoordinator` supplies the few things
/// only it knows through closures: where a display's tile is, which app was in front, how to close
/// the other popovers, and how to reach the Shelf.
///
/// Lifecycle: ``start()`` loads the history and applies the settings; every settings change
/// re-applies only what changed; ``stop()`` closes the panel, stops every source and observer, and
/// writes the history. Background sources never read a protected folder that was not allowed (see
/// `FlixReadPolicy`), so nothing here can make macOS ask for access on its own.
@MainActor @Observable
final class FlixCoordinator {
    let settingsStore: FlixSettingsStore
    let history: FlixHistory
    let intelligence = FlixIntelligence()
    let tile = FlixTileState()
    let panelState: FlixPanelState
    /// Whether the shortcut is held. Settings shows a warning while it is not.
    private(set) var shortcutStatus: FlixShortcutStatus = .off
    /// Pauses the shortcut while the Settings recorder listens, so pressing the current combination
    /// records it instead of opening the panel.
    var isRecordingShortcut = false { didSet { applyShortcut() } }
    private(set) var readPolicy = FlixReadPolicy(allowedRoots: [])
    /// A watched folder is being asked for right now.
    private(set) var requestingAccess: String?

    // MARK: Hooks from DockCoordinator
    /// The tile's anchor on a display (nil: the display under the pointer), with the display's ID.
    @ObservationIgnored var tileAnchor: ((String?) -> (anchor: DockPopoverAnchor, displayID: String)?)?
    /// Closes DOKK's other popovers, the anchored Hub, and Radar before the panel opens.
    @ObservationIgnored var willOpen: ((FlixPanelMode) -> Void)?
    /// The panel opened or closed; anchored panels keep their dock revealed while open.
    @ObservationIgnored var openChanged: ((_ open: Bool, _ displayID: String?) -> Void)?
    /// The last app in front that was not DOKK.
    @ObservationIgnored var previousApplication: (() -> NSRunningApplication?)?
    /// Stages files on the Shelf. False when it refused them.
    @ObservationIgnored var sendToShelf: (([URL]) -> Bool)?
    /// The tile appeared or went away, so the docks rebuild.
    @ObservationIgnored var tileVisibilityChanged: (() -> Void)?
    /// Routes the next Settings window to the Flix Files page.
    @ObservationIgnored var prepareSettings: (() -> Void)?
    /// The panel was opened by any route, for Discovery.
    @ObservationIgnored var didOpen: (() -> Void)?
    /// Stops phase B providers' own background work and flushes their caches; whoever installs
    /// providers appends here (see `installSmartProviders(lookout:robi:)`). Run by ``stop()``.
    @ObservationIgnored var stopProviders: [() -> Void] = []

    @ObservationIgnored private let spotlight = FlixSpotlightSource()
    @ObservationIgnored private let watcher = FlixFolderWatcher()
    @ObservationIgnored private let shortcut = FlixShortcut()
    @ObservationIgnored private var statusItem: FlixStatusItemController?
    @ObservationIgnored private var panel: FlixPanelController?
    @ObservationIgnored private var anchoredDisplayID: String?
    @ObservationIgnored private var previous: NSRunningApplication?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var appSeen: [String: Date] = [:]
    @ObservationIgnored private var watchedRoots: [String] = []
    @ObservationIgnored private var nowTimer: Timer?
    /// Items confirmed by a drop question, so the next drag of them goes ahead. Expires quickly.
    @ObservationIgnored private var confirmedDrag: (ids: Set<FlixItem.ID>, until: Date)?
    @ObservationIgnored private var lookoutFolders: () -> [String]

    /// - Parameters:
    ///   - lookoutFolders: Folders Lookout's setup read with permission; DOKK may read them too.
    init(settings: FlixSettingsStore, history: FlixHistory,
         lookoutFolders: @escaping () -> [String] = { [] }) {
        settingsStore = settings
        self.history = history
        self.lookoutFolders = lookoutFolders
        panelState = FlixPanelState(history: history, intelligence: intelligence, settingsStore: settings)
    }

    /// The live coordinator, reading DOKK's own defaults and Application Support.
    static func live() -> FlixCoordinator {
        FlixCoordinator(settings: FlixSettingsStore(repository: FlixSettingsRepository(defaults: .standard)),
                        history: .live()) {
            let lookout = LookoutSettingsRepository(defaults: .standard).loadOrDefault()
            return lookout.setupCompleted ? lookout.folders : []
        }
    }

    var settings: FlixSettings { settingsStore.settings }
    var isPanelOpen: Bool { panel?.isVisible == true }
    /// Whether the docks show the tile.
    var showsTile: Bool { settings.isEnabled && settings.showsDockTile }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        history.didChange = { [weak self] in self?.historyDidChange() }
        history.load()
        settingsStore.changed = { [weak self] old, new in self?.apply(new, previous: old) }
        configurePanelState()
        apply(settings, previous: nil)
    }

    func stop() {
        guard started else { return }
        started = false
        close(restoreFocus: false, animated: false)
        panel?.stop()
        panel = nil
        spotlight.stop()
        watcher.stop()
        shortcut.stop()
        shortcutStatus = .off
        statusItem?.stop()
        statusItem = nil
        nowTimer?.invalidate()
        nowTimer = nil
        intelligence.stop()
        for stopProvider in stopProviders { stopProvider() }
        tile.stop()
        history.didChange = nil
        settingsStore.changed = nil
        history.flush()
    }

    /// Re-applies what changed between two settings values.
    private func apply(_ new: FlixSettings, previous old: FlixSettings?) {
        intelligence.settings = new
        readPolicy = FlixReadPolicy(settings: new, lookoutFolders: lookoutFolders())
        let enabled = new.isEnabled
        if enabled, new.tracksOpenedFiles { spotlight.start(includingFolders: new.tracksFolders) } else { spotlight.stop() }
        restartWatcher()
        applyShortcut()
        if enabled, new.showsMenuBarItem {
            if statusItem == nil {
                statusItem = FlixStatusItemController(tile: tile) { [weak self] rect in self?.toggleFromMenuBar(rect) }
            }
        } else {
            statusItem?.stop()
            statusItem = nil
        }
        if !enabled { close(restoreFocus: false) }
        if old == nil || old?.isEnabled != new.isEnabled || old?.showsDockTile != new.showsDockTile {
            tileVisibilityChanged?()
        }
        historyDidChange()
    }

    private func applyShortcut() {
        guard started, settings.isEnabled, settings.shortcutEnabled, !isRecordingShortcut else {
            shortcut.stop()
            shortcutStatus = isRecordingShortcut ? .paused : .off
            return
        }
        if shortcut.registered == settings.shortcut { return }
        shortcutStatus = shortcut.start(settings.shortcut) { [weak self] in
            Analytics.performing(.keyboard) { self?.toggleAtPointer() }
        } ? .registered : .unavailable
    }

    private func restartWatcher() {
        let roots = settings.isEnabled && settings.tracksWatchedFolders
            ? settings.enabledWatchedFolders.map(\.path).filter(readPolicy.canRead) : []
        guard roots != watchedRoots else { return }
        watchedRoots = roots
        watcher.start(folders: roots) { [weak self] events in self?.receive(events) }
    }

    private func configurePanelState() {
        spotlight.deliver = { [weak self] events in self?.receive(events) }
        panelState.close = { [weak self] restore in self?.close(restoreFocus: restore) }
        panelState.toggleQuickLook = { [weak self] urls in self?.panel?.toggleQuickLook(urls) }
        panelState.quickLookSelectionChanged = { [weak self] urls in self?.panel?.quickLook.update(urls) }
        panelState.sendToShelf = { [weak self] urls in self?.sendToShelf?(urls) ?? false }
        panelState.requestFolderAccess = { [weak self] path in self?.requestAccess(path) }
        panelState.prepareSettings = { [weak self] in
            self?.prepareSettings?()
            self?.close(restoreFocus: false)
        }
        panelState.beginDrag = { [weak self] ids, view, event in self?.beginDrag(ids, from: view, event: event) }
        panelState.confirmDrag = { [weak self] ids in self?.confirmDrag(ids) }
    }

    // MARK: Sources

    /// Merges events, dropping what the settings do not track.
    private func receive(_ events: [FlixActivityEvent]) {
        let settings = settings
        let kept = events.filter { event in
            if event.kind == .folder, !settings.tracksFolders { return false }
            if event.kind == .app, !settings.tracksApps { return false }
            return true
        }
        guard !kept.isEmpty else { return }
        history.record(kept)
    }

    /// An app came to the front. Refreshes the tile's ✦ pill when a provider can read the window, and
    /// records the app at most every five minutes, so switching back and forth does not bury the
    /// files. Window switches inside one app are phase B1's to observe.
    func applicationActivated(_ app: NSRunningApplication) {
        guard started, settings.isEnabled, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if !isPanelOpen, settings.showsFitsOnTile, intelligence.providers.fits != nil {
            intelligence.frontWindowChanged(FlixFrontmostContext.capture(fallback: nil), items: history.items)
        }
        guard settings.tracksApps, app.activationPolicy == .regular, let id = app.bundleIdentifier,
              id != "com.apple.finder", let url = app.bundleURL else { return }
        let now = Date.now
        if let seen = appSeen[id], now.timeIntervalSince(seen) < 300 { return }
        appSeen[id] = now
        history.record(FlixActivityEvent(path: url.path, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                                         kind: .app, activity: .opened, date: now,
                                         contentTypeIdentifier: "com.apple.application-bundle", bundleIdentifier: id))
    }

    private func historyDidChange() {
        let hiding = settings.hidesNoise
        let newest = history.newest(hidingNoise: hiding)
        tile.update(newest: newest, unseen: isPanelOpen ? 0 : history.unseenCount(hidingNoise: hiding),
                    sensitive: newest.flatMap { intelligence.annotations[$0.id]?.isSensitive } ?? false,
                    policy: readPolicy)
        tile.fitCount = isPanelOpen ? nil : intelligence.tileFitCount
        statusItem?.update()
        intelligence.historyChanged(items: history.items)
    }

    // MARK: Folder access

    /// Asks macOS for a watched folder. Only ever called from a button the person pressed.
    func requestAccess(_ path: String) {
        guard requestingAccess == nil else { return }
        requestingAccess = path
        Task { [weak self] in
            let access = await FlixReadPolicy.requestAccess(path)
            guard let self else { return }
            requestingAccess = nil
            settingsStore.setAccess(access, for: path)
            panelState.foldersAwaitingAccess.removeAll { $0.path == path }
        }
    }

    /// Adds a folder chosen in an open panel and asks for it right away, since choosing it was the
    /// explicit request.
    func addWatchedFolder(_ url: URL) {
        let path = FlixPaths.standardized(url.path)
        let policy = FlixReadPolicy(allowedRoots: [])
        settingsStore.addWatchedFolder(path, access: policy.isProtected(path) ? .unknown : .allowed)
        if policy.isProtected(path) { requestAccess(path) }
    }

    // MARK: Opening and closing

    /// A click on a display's tile.
    func toggleFromTile(displayID: String) {
        if isPanelOpen { close(restoreFocus: true); return }
        guard let (anchor, id) = tileAnchor?(displayID) else { return }
        let placement = FlixPanelGeometry.anchored(tile: anchor.icon, edge: anchor.edge, visibleFrame: anchor.visibleFrame)
        open(mode: .anchored, body: placement.body, growth: placement.growth, displayID: id)
    }

    /// The shortcut: at the pointer, newest item selected, keyboard focus in the panel.
    func toggleAtPointer() {
        if isPanelOpen { close(restoreFocus: true); return }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        let placement = FlixPanelGeometry.atPointer(pointer, visibleFrame: screen.visibleFrame)
        open(mode: .pointer, body: placement.body, growth: placement.growth, displayID: nil)
    }

    /// Opens from Discovery or a menu: anchored when a tile shows, else at the pointer.
    func openFromAnywhere() {
        guard !isPanelOpen else { return }
        if showsTile, let (anchor, id) = tileAnchor?(nil) {
            let placement = FlixPanelGeometry.anchored(tile: anchor.icon, edge: anchor.edge, visibleFrame: anchor.visibleFrame)
            open(mode: .anchored, body: placement.body, growth: placement.growth, displayID: id)
        } else {
            toggleAtPointer()
        }
    }

    private func toggleFromMenuBar(_ itemRect: CGRect) {
        if isPanelOpen { close(restoreFocus: true); return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(itemRect) }) ?? NSScreen.main else { return }
        let placement = FlixPanelGeometry.anchored(tile: itemRect, edge: .top, visibleFrame: screen.visibleFrame)
        open(mode: .pointer, body: placement.body, growth: placement.growth, displayID: nil)
    }

    private func open(mode: FlixPanelMode, body: CGRect, growth: FlixGrowthAnchor, displayID: String?) {
        guard settings.isEnabled else { return }
        // Read before anything can take focus: the window in front is what "Fits" reads.
        previous = previousApplication?() ?? NSWorkspace.shared.frontmostApplication
        let context = FlixFrontmostContext.capture(fallback: previous)
        willOpen?(mode)
        let panel = panel ?? makePanel()
        panelState.prepareForOpen(mode: mode, frontmost: context, policy: readPolicy)
        intelligence.panelOpened(context: context, items: history.items)
        anchoredDisplayID = mode == .anchored ? displayID : nil
        panel.show(body: body, growth: growth)
        history.markSeen()
        tile.isPanelOpen = true
        openChanged?(true, anchoredDisplayID)
        performOnOpen()
        showPendingNotice()
        startClock()
        didOpen?()
    }

    /// Shows drag memory's "Flix noticed" message as a toast, once: right after the drop when the
    /// panel stays open, otherwise on the next open.
    private func showPendingNotice() {
        guard let notice = intelligence.notice else { return }
        intelligence.notice = nil
        panelState.showToast(notice)
    }

    /// Closes the panel. `restoreFocus` reactivates the app that was in front before it opened.
    func close(restoreFocus: Bool, animated: Bool = true) {
        guard let panel, panel.isVisible else { return }
        let previous = previous
        self.previous = nil
        let displayID = anchoredDisplayID
        anchoredDisplayID = nil
        panelState.panelDidClose()
        intelligence.panelClosed()
        nowTimer?.invalidate()
        nowTimer = nil
        panel.close(animated: animated)
        tile.isPanelOpen = false
        historyDidChange()
        openChanged?(false, displayID)
        if restoreFocus, NSApp.isActive, let previous, !previous.isTerminated { previous.activate(options: []) }
    }

    /// Follows the tile when the dock moves while the panel is anchored to it.
    func reanchor() {
        guard isPanelOpen, let id = anchoredDisplayID else { return }
        guard let (anchor, _) = tileAnchor?(id), showsTile else { close(restoreFocus: false); return }
        let placement = FlixPanelGeometry.anchored(tile: anchor.icon, edge: anchor.edge, visibleFrame: anchor.visibleFrame)
        panel?.reanchor(body: placement.body, growth: placement.growth)
    }

    private func makePanel() -> FlixPanelController {
        let controller = FlixPanelController(state: panelState, content: FlixPanelView(state: panelState))
        controller.outsideClick = { [weak self] event in
            guard let self, panelState.drag == nil else { return false }
            close(restoreFocus: false)
            // A dock click dismisses the panel but must not also reach the tile under it.
            return event?.window is DockPanel
        }
        controller.applicationResigned = { [weak self] in
            guard let self, panelState.drag == nil, panel?.quickLook.isVisible != true else { return }
            close(restoreFocus: false)
        }
        panel = controller
        return controller
    }

    /// Settings' "When Flix Files opens".
    private func performOnOpen() {
        guard let newest = history.newest(hidingNoise: settings.hidesNoise) else { return }
        switch settings.onOpen {
        case .nothing: break
        case .copyNewest:
            FlixFileActions.copy([newest])
            panelState.showToast(String(localized: .flixToastCopied(panelState.label(for: [newest]))))
        case .copyNewestPath:
            FlixFileActions.copyPaths([newest])
            panelState.showToast(String(localized: .flixToastCopiedPath(1)))
        }
    }

    /// Keeps relative times and sections current while the panel is open: once a minute, only then.
    private func startClock() {
        nowTimer?.invalidate()
        nowTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelState.now = .now }
        }
    }

    // MARK: Dragging out

    /// Starts a drag of rows or a thread card from the panel.
    ///
    /// The drop questions (a sensitive file, an older version) run here, before the drag starts:
    /// macOS never tells a drag source where the drop will land, so Flix asks about the window that
    /// was in front when it opened. Answering lets the next drag of the same items go ahead for 30
    /// seconds. Phase B1's conversions replace files on the pasteboard through the plan.
    func beginDrag(_ ids: [FlixItem.ID], from view: NSView, event: NSEvent) {
        let items = ids.compactMap(history.item)
        guard !items.isEmpty else { return }
        let set = Set(ids)
        let confirmed = confirmedDrag.map { $0.until > .now && set.isSubset(of: $0.ids) } ?? false
        if !confirmed, let question = intelligence.dropConfirmation(for: items, context: panelState.frontmost) {
            panelState.confirmation = FlixPendingConfirmation(confirmation: question, itemIDs: ids)
            return
        }
        let plan = intelligence.dragPlan(for: items, context: panelState.frontmost)
        let icons = Dictionary(uniqueKeysWithValues: items.map { ($0.id, FlixIconProvider.icon(for: $0, policy: readPolicy)) })
        panelState.drag = FlixDragActivity(itemIDs: ids)
        let started = FlixDragSession.begin(items: items, substitutions: plan?.substitutions ?? [:], icons: icons,
                                            from: view, event: event,
                                            moved: { [weak self] point in self?.dragMoved(to: point) },
                                            ended: { [weak self] accepted, _ in self?.dragEnded(items, accepted: accepted) })
        if !started { panelState.drag = nil }
    }

    /// Lets the next drag of `ids` skip the drop questions, after the person answered one.
    func confirmDrag(_ ids: [FlixItem.ID]) {
        confirmedDrag = (Set(ids), Date.now.addingTimeInterval(30))
    }

    /// Drags the newest item straight off the tile.
    func beginTileDrag(from view: NSView, event: NSEvent) {
        guard let newest = history.newest(hidingNoise: settings.hidesNoise) else { return }
        if intelligence.dropConfirmation(for: [newest], context: FlixFrontmostContext.capture(fallback: nil)) != nil,
           confirmedDrag.map({ $0.until > .now && $0.ids.contains(newest.id) }) != true {
            // The question needs the panel; open it on the tile with the question showing.
            openFromAnywhere()
            panelState.confirmation = intelligence.dropConfirmation(for: [newest], context: panelState.frontmost)
                .map { FlixPendingConfirmation(confirmation: $0, itemIDs: [newest.id]) }
            return
        }
        let plan = intelligence.dragPlan(for: [newest], context: FlixFrontmostContext.capture(fallback: nil))
        let icon = tile.thumbnail ?? FlixIconProvider.typeIcon(for: newest)
        FlixDragSession.begin(items: [newest], substitutions: plan?.substitutions ?? [:], icons: [newest.id: icon],
                              from: view, event: event, moved: { _ in },
                              ended: { [weak self] accepted, _ in
                                  if accepted { self?.intelligence.recordDrop(of: [newest], context: nil) }
                              })
    }

    private func dragMoved(to point: CGPoint) {
        guard let panel, var drag = panelState.drag else { return }
        let outside = !panel.contains(point)
        guard outside != drag.isOutside else { return }
        drag.isOutside = outside
        panelState.drag = drag
        panel.stepAside(outside)
    }

    /// After a drop outside, the panel closes unless pinned; after a cancelled drag it comes back.
    private func dragEnded(_ items: [FlixItem], accepted: Bool) {
        let wasOutside = panelState.drag?.isOutside ?? false
        panelState.drag = nil
        guard let panel, panel.isVisible else { return }
        guard wasOutside else { return }
        if accepted { intelligence.recordDrop(of: items, context: panelState.frontmost) }
        if accepted, !panelState.staysOpenAfterDrag {
            close(restoreFocus: false, animated: false)
        } else {
            showPendingNotice()
            DispatchQueue.main.asyncAfter(deadline: .now() + (accepted ? 0.26 : 0)) { [weak panel] in
                panel?.stepAside(false)
            }
        }
    }

    // MARK: Dropping in

    /// Files dropped on a dock tile: kept as items, a deliberate save.
    func keepDroppedFiles(_ urls: [URL]) {
        panelState.keep(files: urls, links: [])
    }
}

/// Whether the Flix shortcut is held.
enum FlixShortcutStatus: Equatable {
    case off
    case registered
    /// Another app holds the combination.
    case unavailable
    /// Paused while Settings records a new one.
    case paused
}
