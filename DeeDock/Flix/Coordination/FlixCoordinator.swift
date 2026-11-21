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
///
/// The master switch (`FlixSettings.isEnabled`) gates everything that runs in the background:
/// while it is off no source, observer, provider pass, worker, or conversion starts, including at
/// launch, and turning it off cancels what is running (``suspendBackgroundWork()``). The history
/// stays on disk and the tile simply disappears.
@MainActor @Observable
final class FlixCoordinator {
    let settingsStore: FlixSettingsStore
    let history: FlixHistory
    let intelligence = FlixIntelligence()
    let tile = FlixTileState()
    let panelState: FlixPanelState
    /// The open panel visit's analytics (`flix_session_ended` and the visits inside it).
    @ObservationIgnored let metrics = FlixSessionMetrics()
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
    /// Cancels phase B providers' running work without tearing them down, for when Flix Files is
    /// switched off. Their next pass starts it again once it is back on.
    @ObservationIgnored var pauseProviders: [() -> Void] = []

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
    /// The read policy the watcher was started with; it re-checks every event path against it.
    @ObservationIgnored private var watchedPolicy = FlixReadPolicy(allowedRoots: [])
    @ObservationIgnored private var nowTimer: Timer?
    /// Items confirmed by a drop question, so the next drag of them goes ahead. Expires quickly.
    @ObservationIgnored private var confirmedDrag: (ids: Set<FlixItem.ID>, until: Date)?
    /// When the open in progress was asked for (a tile click or the shortcut), until its first frame.
    @ObservationIgnored private var openRequestedAt: ContinuousClock.Instant?
    /// What DOKK's dock said it received from the drag in flight.
    @ObservationIgnored private var dockDropTarget: AnalyticsFlixDropTarget?
    /// The last shortcut a registration was reported for, so only changes report again.
    @ObservationIgnored private var reportedShortcut: FlixShortcutCombo?
    @ObservationIgnored private var lookoutFolders: () -> [String]
    /// The background pass that records identities for rows without one (``captureMissingIdentities()``).
    @ObservationIgnored private var identityTask: Task<Void, Never>?
    /// Rows the pass already looked at, by path and date, so a file that cannot be read is not
    /// looked at again until it has new activity.
    @ObservationIgnored private var identityAttempted = Set<String>()
    /// Phase B1's window reading, conversions, sensitive guard, and web links. Set by ``live()``;
    /// nil in previews and tests, where Flix Files runs without them.
    @ObservationIgnored var contextServices: FlixContextServices?

    /// - Parameters:
    ///   - lookoutFolders: Folders Lookout's setup read with permission; DOKK may read them too.
    init(settings: FlixSettingsStore, history: FlixHistory,
         lookoutFolders: @escaping () -> [String] = { [] }) {
        settingsStore = settings
        self.history = history
        self.lookoutFolders = lookoutFolders
        panelState = FlixPanelState(history: history, intelligence: intelligence, settingsStore: settings)
        panelState.metrics = metrics
        intelligence.metrics = metrics
        metrics.panel = panelState
    }

    /// The live coordinator, reading DOKK's own defaults and Application Support.
    static func live() -> FlixCoordinator {
        let history = FlixHistory.live()
        let coordinator = FlixCoordinator(settings: FlixSettingsStore(repository: FlixSettingsRepository(defaults: .standard)),
                                          history: history) {
            let lookout = LookoutSettingsRepository(defaults: .standard).loadOrDefault()
            return lookout.setupCompleted ? lookout.folders : []
        }
        coordinator.contextServices = FlixContextServices(history: history, folder: FlixStorageLocation.folder())
        return coordinator
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
        contextServices?.start(with: self)
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
        identityTask?.cancel()
        identityTask = nil
        identityAttempted = []
        contextServices?.stop()
        intelligence.stop()
        for stopProvider in stopProviders { stopProvider() }
        tile.stop()
        history.didChange = nil
        settingsStore.changed = nil
        history.flush()
    }

    /// Re-applies what changed between two settings values.
    private func apply(_ new: FlixSettings, previous old: FlixSettings?) {
        let enabled = new.isEnabled
        if !enabled, old?.isEnabled != false { suspendBackgroundWork() }
        intelligence.settings = new
        readPolicy = FlixReadPolicy(settings: new, lookoutFolders: lookoutFolders())
        contextServices?.apply(new)
        // At launch this also migrates download pages stored under the earlier, looser policy.
        if old == nil || old?.isEnabled != new.isEnabled || old?.tracksLinks != new.tracksLinks
            || old?.excludedSites != new.excludedSites || old?.excludesSensitiveSites != new.excludesSensitiveSites {
            history.applySourcePolicy(new)
        }
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

    /// Flix Files was switched off: cancels every pass, worker, and timer that runs on its own.
    /// Sources and observers stop through ``apply(_:previous:)``; providers' caches stay for later.
    private func suspendBackgroundWork() {
        close(restoreFocus: false, animated: false)
        identityTask?.cancel()
        identityTask = nil
        identityAttempted = []
        tile.suspend()
        intelligence.stop()
        for pause in pauseProviders { pause() }
        contextServices?.suspend()
    }

    private func applyShortcut() {
        guard started, settings.isEnabled, settings.shortcutEnabled, !isRecordingShortcut else {
            shortcut.stop()
            shortcutStatus = isRecordingShortcut ? .paused : .off
            return
        }
        if shortcut.registered == settings.shortcut { return }
        shortcutStatus = shortcut.start(settings.shortcut) { [weak self] in
            Analytics.performing(.keyboard) { self?.toggleAtPointer(trigger: .shortcut) }
        } ? .registered : .unavailable
        reportShortcutRegistration()
    }

    /// `flix_shortcut_registration`: at launch only when the combination is taken, and after every
    /// change of the combination.
    private func reportShortcutRegistration() {
        let combo = settings.shortcut
        let changed = reportedShortcut != nil && reportedShortcut != combo
        defer { reportedShortcut = combo }
        guard changed || (reportedShortcut == nil && shortcutStatus == .unavailable) else { return }
        Analytics.track(.flixShortcutRegistration(shortcutStatus == .registered ? .registered : .unavailable,
                                                  customized: combo != .default, combo: AnalyticsShortcutCombo(combo)))
    }

    private func restartWatcher() {
        let roots = settings.isEnabled && settings.tracksWatchedFolders
            ? settings.enabledWatchedFolders.map(\.path).filter(readPolicy.canRead) : []
        guard roots != watchedRoots || readPolicy != watchedPolicy else { return }
        watchedRoots = roots
        watchedPolicy = readPolicy
        watcher.start(folders: roots, policy: readPolicy) { [weak self] events in self?.receive(events) }
    }

    private func configurePanelState() {
        spotlight.deliver = { [weak self] events in self?.receive(events) }
        // Only Escape asks to restore focus; every other close from the panel hands over to an app.
        panelState.close = { [weak self] restore in self?.close(restoreFocus: restore, reason: restore ? .escape : .other) }
        panelState.toggleQuickLook = { [weak self] urls in self?.panel?.toggleQuickLook(urls) }
        panelState.quickLookSelectionChanged = { [weak self] urls in self?.panel?.quickLook.update(urls) }
        panelState.sendToShelf = { [weak self] urls in self?.sendToShelf?(urls) ?? false }
        panelState.requestFolderAccess = { [weak self] path in self?.requestAccess(path) }
        panelState.prepareSettings = { [weak self] in
            self?.prepareSettings?()
            self?.close(restoreFocus: false)
        }
        panelState.beginDrag = { [weak self] ids, view, event, origin in
            self?.beginDrag(ids, from: view, event: event, origin: origin)
        }
        panelState.confirmDrag = { [weak self] ids in self?.confirmDrag(ids) }
    }

    // MARK: Sources

    /// Merges events, dropping what the settings do not track and download pages they do not
    /// allow (``FlixSourcePolicy``), before anything reaches the history or the link tracker.
    ///
    /// The history takes only a download's host: a full page address reaches a file row only once
    /// the link tracker verified the download came from a normal window showing that page
    /// (`FlixLinkTracker.recorded(_:)`), which then attaches it.
    private func receive(_ events: [FlixActivityEvent]) {
        let settings = settings
        // A source stopped by the master switch may still deliver its last batch.
        guard settings.isEnabled else { return }
        let kept = events.filter { event in
            if event.kind == .folder, !settings.tracksFolders { return false }
            if event.kind == .app, !settings.tracksApps { return false }
            return true
        }.map { FlixSourcePolicy.apply(to: $0, settings: settings) }
        guard !kept.isEmpty else { return }
        countRecorded(kept)
        history.record(kept.map { event in
            var stored = event
            stored.sourcePage = nil
            return stored
        })
        contextServices?.recorded(kept)
    }

    /// `usage_summary` counts of what the sources recorded, and how much of it is noise.
    private func countRecorded(_ events: [FlixActivityEvent]) {
        for event in events {
            switch event.activity {
            case .opened where event.kind == .app: Analytics.count(.itemsApp)
            case .opened: Analytics.count(.itemsOpened)
            case .downloaded: Analytics.count(.itemsDownloaded)
            case .created: Analytics.count(.itemsNew)
            case .saved, .kept: Analytics.count(.itemsSaved)
            case .link: break
            }
        }
        if settings.hidesNoise {
            Analytics.count(.noiseFiltered, by: events.count { FlixNoiseRules.isNoise(path: $0.path) })
        }
    }

    /// An app came to the front. Records the app at most every five minutes, so switching back and
    /// forth does not bury the files. Without phase B1's services it also refreshes the tile's ✦
    /// pill; with them, `FlixFrontWindowObserver` does that for app and window switches alike.
    func applicationActivated(_ app: NSRunningApplication) {
        guard started, settings.isEnabled, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        // With phase B1's services, their front-window observer refreshes the pill instead.
        if contextServices == nil, !isPanelOpen, settings.showsFitsOnTile, intelligence.providers.fits != nil {
            intelligence.frontWindowChanged(FlixFrontmostContext.capture(fallback: nil), items: history.items)
        }
        guard settings.tracksApps, app.activationPolicy == .regular, let id = app.bundleIdentifier,
              id != "com.apple.finder", let url = app.bundleURL else { return }
        let now = Date.now
        if let seen = appSeen[id], now.timeIntervalSince(seen) < 300 { return }
        appSeen[id] = now
        Analytics.count(.itemsApp)
        history.record(FlixActivityEvent(path: url.path, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                                         kind: .app, activity: .opened, date: now,
                                         contentTypeIdentifier: "com.apple.application-bundle", bundleIdentifier: id))
    }

    private func historyDidChange() {
        refreshTile()
        // No analysis, guard pass, identity pass, or link index while Flix Files is off.
        guard settings.isEnabled else { return }
        intelligence.historyChanged(items: history.items)
        contextServices?.historyChanged(history.items)
        captureMissingIdentities()
    }

    /// Rows read per identity pass.
    static let identityBatch = 300

    /// Records the file identity of rows that have none yet (Spotlight's rows, and rows whose file
    /// had new activity), so Trash, Move, and Rename can tell a replaced file apart
    /// (``FlixFileOperations/check(_:)``). Off the main actor on the file worker, only for paths
    /// the read policy allows, at most ``identityBatch`` rows per pass; storing them changes the
    /// history, which starts the next pass until every readable row has one.
    private func captureMissingIdentities() {
        guard identityTask == nil else { return }
        var pending: [(id: FlixItem.ID, path: String)] = []
        for item in history.items where item.fileIdentity == nil && item.link == nil {
            guard let path = item.path else { continue }
            guard identityAttempted.insert(path + "|\(item.date.timeIntervalSinceReferenceDate)").inserted else { continue }
            pending.append((item.id, path))
            if pending.count >= Self.identityBatch { break }
        }
        guard !pending.isEmpty else { return }
        let policy = readPolicy
        let paths = pending.map(\.path)
        identityTask = Task { [weak self] in
            let found = await FlixFileWorker.shared.run { FlixFileOperations.identities(of: paths, policy: policy) }
            guard let self, !Task.isCancelled else { return }
            identityTask = nil
            history.setIdentities(pending.compactMap { entry in
                found[entry.path].map { (entry.id, entry.path, $0) }
            })
        }
    }

    /// Redraws the tile (and the menu bar item) from the history and the intelligence slots.
    ///
    /// While Flix Files is off the tile is hidden: nothing is read, no thumbnail is requested, and
    /// the read policy is never consulted. Turning it back on refreshes the tile from scratch.
    func refreshTile() {
        guard settings.isEnabled else {
            tile.suspend()
            statusItem?.update()
            return
        }
        let hiding = settings.hidesNoise
        let newest = history.newest(hidingNoise: hiding)
        let guarded = settings.guardsSensitiveFiles
        tile.update(newest: newest, unseen: isPanelOpen ? 0 : history.unseenCount(hidingNoise: hiding),
                    sensitive: guarded && (newest.flatMap { intelligence.annotations[$0.id]?.isSensitive } ?? false),
                    policy: readPolicy)
        let fitCount = isPanelOpen ? nil : intelligence.tileFitCount
        if fitCount != nil, fitCount != tile.fitCount { Analytics.count(.fitsPillShown) }
        tile.fitCount = fitCount
        statusItem?.update()
    }

    // MARK: Folder access

    /// Asks macOS for a watched folder. Only ever called from a button the person pressed.
    func requestAccess(_ path: String) {
        guard requestingAccess == nil else { return }
        requestingAccess = path
        Task { [weak self] in
            let access = await FlixReadPolicy.requestAccess(path)
            Analytics.track(.flixFolderAccess(access == .allowed ? .granted : .denied, folder: AnalyticsFlixFolder(path: path)))
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
        if isPanelOpen { close(restoreFocus: true, reason: .clickedAway); return }
        let requested = ContinuousClock.now
        guard let (anchor, id) = tileAnchor?(displayID) else { return }
        if tile.fitCount != nil { Analytics.count(.tileClickedWithPill) }
        let placement = FlixPanelGeometry.anchored(tile: anchor.icon, edge: anchor.edge, visibleFrame: anchor.visibleFrame)
        open(mode: .anchored, body: placement.body, growth: placement.growth, displayID: id,
             trigger: .tileClick, placement: .tile, requestedAt: requested)
    }

    /// The shortcut: at the pointer, newest item selected, keyboard focus in the panel.
    ///
    /// - Parameter trigger: What asked; Discovery and menus fall back here when no tile shows.
    func toggleAtPointer(trigger: AnalyticsFlixTrigger = .shortcut) {
        if isPanelOpen { close(restoreFocus: true, reason: trigger == .shortcut ? .shortcutToggle : .clickedAway); return }
        let requested = ContinuousClock.now
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        let placement = FlixPanelGeometry.atPointer(pointer, visibleFrame: screen.visibleFrame)
        open(mode: .pointer, body: placement.body, growth: placement.growth, displayID: nil,
             trigger: trigger, placement: .pointer, requestedAt: trigger == .shortcut ? requested : nil)
    }

    /// Opens from Discovery or a menu: anchored when a tile shows, else at the pointer.
    func openFromAnywhere(trigger: AnalyticsFlixTrigger = .discovery) {
        guard !isPanelOpen else { return }
        if showsTile, let (anchor, id) = tileAnchor?(nil) {
            let placement = FlixPanelGeometry.anchored(tile: anchor.icon, edge: anchor.edge, visibleFrame: anchor.visibleFrame)
            open(mode: .anchored, body: placement.body, growth: placement.growth, displayID: id,
                 trigger: trigger, placement: .tile, requestedAt: nil)
        } else {
            toggleAtPointer(trigger: trigger)
        }
    }

    private func toggleFromMenuBar(_ itemRect: CGRect) {
        if isPanelOpen { close(restoreFocus: true, reason: .clickedAway); return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(itemRect) }) ?? NSScreen.main else { return }
        let placement = FlixPanelGeometry.anchored(tile: itemRect, edge: .top, visibleFrame: screen.visibleFrame)
        open(mode: .pointer, body: placement.body, growth: placement.growth, displayID: nil,
             trigger: .menuBar, placement: .menuBar, requestedAt: nil)
    }

    /// - Parameter requestedAt: When a tile click or the shortcut asked, for the open-latency counters
    ///   (request → first frame); nil for other routes.
    private func open(mode: FlixPanelMode, body: CGRect, growth: FlixGrowthAnchor, displayID: String?,
                      trigger: AnalyticsFlixTrigger, placement: AnalyticsFlixPlacement,
                      requestedAt: ContinuousClock.Instant?) {
        guard settings.isEnabled else { return }
        // Read before anything can take focus: the window in front is what "Fits" reads.
        previous = previousApplication?() ?? NSWorkspace.shared.frontmostApplication
        let context = FlixFrontmostContext.capture(fallback: previous)
        willOpen?(mode)
        let panel = panel ?? makePanel()
        panelState.prepareForOpen(mode: mode, frontmost: context, policy: readPolicy)
        metrics.begin(trigger: trigger, placement: placement, displayBuiltin: Self.isBuiltIn(body),
                      front: FlixAppCategory.of(context), unseen: history.unseenCount(hidingNoise: settings.hidesNoise),
                      listSize: panelState.list.count)
        if !settings.suggestsForFrontWindow { metrics.fitsRead(reader: .disabled, readyMs: nil, shown: 0) }
        openRequestedAt = requestedAt
        intelligence.panelOpened(context: context, items: history.items)
        if intelligence.filterTip != nil { Analytics.track(.flixTipShown(.smartFilter)) }
        contextServices?.panelOpened(context)
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

    /// Closes the panel. `restoreFocus` reactivates the app that was in front before it opened;
    /// `reason` is how the visit ended, for its `flix_session_ended`.
    func close(restoreFocus: Bool, animated: Bool = true, reason: FlixCloseReason = .other) {
        guard let panel, panel.isVisible else { return }
        // First, while the panel still shows what the visit ended on.
        metrics.end(reason: reason, pinned: panelState.isPinned)
        openRequestedAt = nil
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
            close(restoreFocus: false, reason: .clickedAway)
            // A dock click dismisses the panel but must not also reach the tile under it.
            return event?.window is DockPanel
        }
        controller.applicationResigned = { [weak self] in
            guard let self, panelState.drag == nil, panel?.quickLook.isVisible != true else { return }
            close(restoreFocus: false, reason: .clickedAway)
        }
        controller.pointerPressed = { [weak self] in self?.metrics.pointerPressed() }
        controller.firstFrame = { [weak self] in self?.recordOpenLatency() }
        panel = controller
        return controller
    }

    /// The open-latency counters: from the click or shortcut to the panel's first frame.
    private func recordOpenLatency() {
        guard let requested = openRequestedAt else { return }
        openRequestedAt = nil
        Analytics.countTiming(sum: .openLatencySum, count: .openLatencyCount, max: .openLatencyMax,
                              milliseconds: Int((ContinuousClock.now - requested) / .milliseconds(1)))
    }

    /// Whether the display under `body` is the Mac's built-in one.
    private static func isBuiltIn(_ body: CGRect) -> Bool {
        let center = CGPoint(x: body.midX, y: body.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(number.uint32Value) != 0
    }

    /// Settings' "When Flix Files opens".
    private func performOnOpen() {
        guard let newest = history.newest(hidingNoise: settings.hidesNoise) else { return }
        switch settings.onOpen {
        case .nothing: break
        case .copyNewest:
            panelState.reportAction(.copy, [newest], origin: .list)
            FlixFileActions.copy([newest])
            panelState.showToast(String(localized: .flixToastCopied(panelState.label(for: [newest]))))
        case .copyNewestPath:
            panelState.reportAction(.copy, [newest], origin: .list)
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
    /// macOS never tells a drag source where the drop will land. A flagged file is asked about on
    /// every drag, whichever app is in front (`FlixDragInterceptor.confirmation(for:context:)`).
    /// Answering lets the next drag of the same items go ahead for 30 seconds. Phase B1's conversions replace files on the pasteboard through the plan, but only
    /// while the window the panel read is still the one in front: the copies are for that upload.
    func beginDrag(_ ids: [FlixItem.ID], from view: NSView, event: NSEvent, origin: FlixActionOrigin = .list) {
        let items = ids.compactMap(history.item)
        guard !items.isEmpty else { return }
        panelState.dragOrigin = origin
        panelState.dragFromTile = false
        let set = Set(ids)
        let confirmed = confirmedDrag.map { $0.until > .now && set.isSubset(of: $0.ids) } ?? false
        if !confirmed, let question = intelligence.dropConfirmation(for: items, context: panelState.frontmost) {
            panelState.confirmation = FlixPendingConfirmation(confirmation: question, itemIDs: ids)
            return
        }
        let stillInFront = panelState.frontmost?.isStillInFront(fallback: previous ?? previousApplication?()) == true
        let plan = stillInFront ? intelligence.dragPlan(for: items, context: panelState.frontmost) : nil
        let icons = Dictionary(uniqueKeysWithValues: items.map {
            ($0.id, dragIcon(for: $0, base: FlixIconProvider.icon(for: $0, policy: readPolicy)))
        })
        panelState.drag = FlixDragActivity(itemIDs: ids)
        dockDropTarget = nil
        // Read where the first item sits now: the list may change before the drop.
        let place = panelState.analyticsPlace(of: items[0].id, origin: origin)
        let warning = panelState.takeAnsweredWarning(for: ids)
        let started = FlixDragSession.begin(items: items, substitutions: plan?.substitutions ?? [:], icons: icons,
                                            label: plan?.label,
                                            from: view, event: event,
                                            moved: { [weak self] point in self?.dragMoved(to: point) },
                                            ended: { [weak self] accepted, point in
                                                self?.dragEnded(items, accepted: accepted, at: point, plan: plan,
                                                                place: place, warning: warning)
                                            })
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
            openFromAnywhere(trigger: .tileDrag)
            panelState.dragOrigin = nil
            panelState.dragFromTile = true
            panelState.confirmation = intelligence.dropConfirmation(for: [newest], context: panelState.frontmost)
                .map { FlixPendingConfirmation(confirmation: $0, itemIDs: [newest.id]) }
            return
        }
        let front = FlixFrontmostContext.capture(fallback: nil)
        let plan = intelligence.dragPlan(for: [newest], context: front)
        let icon = dragIcon(for: newest, base: tile.thumbnail ?? FlixIconProvider.typeIcon(for: newest))
        let warning = panelState.takeAnsweredWarning(for: [newest.id])
        let predicted = intelligence.likelyItem(for: front, among: history.items) == newest.id
        dockDropTarget = nil
        FlixDragSession.begin(items: [newest], substitutions: plan?.substitutions ?? [:], icons: [newest.id: icon],
                              label: plan?.label, from: view, event: event, moved: { _ in },
                              ended: { [weak self] accepted, point in
                                  guard accepted, let self else { return }
                                  reportDrop([newest], source: .tile, place: nil, at: point, front: front, plan: plan,
                                             warning: warning, predicted: predicted)
                                  intelligence.recordDrop(of: [newest], context: nil)
                                  contextServices?.dropped([newest], context: front)
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
    private func dragEnded(_ items: [FlixItem], accepted: Bool, at point: CGPoint, plan: FlixDragPlan?,
                           place: (section: AnalyticsFlixSection, rank: Int?)?, warning: FlixAnsweredWarning?) {
        let wasOutside = panelState.drag?.isOutside ?? false
        panelState.drag = nil
        guard let panel, panel.isVisible else { return }
        guard wasOutside else { return }
        if accepted {
            let source = panelState.dragSource
            metrics.acted(.drag, items: items, at: place)
            if source == .threadCard, let thread = intelligence.thread(containing: items[0].id) {
                panelState.reportThread(.dragCard, thread)
            }
            let predicted = intelligence.likelyItem(for: panelState.frontmost, among: history.items)
                .map { id in items.contains { $0.id == id } } ?? false
            reportDrop(items, source: source, place: place, at: point, front: panelState.frontmost, plan: plan,
                       warning: warning, predicted: predicted)
            intelligence.recordDrop(of: items, context: panelState.frontmost)
            contextServices?.dropped(items, context: panelState.frontmost)
        }
        if accepted, !panelState.staysOpenAfterDrag {
            close(restoreFocus: false, animated: false)
        } else {
            showPendingNotice()
            DispatchQueue.main.asyncAfter(deadline: .now() + (accepted ? 0.26 : 0)) { [weak panel] in
                panel?.stepAside(false)
            }
        }
    }

    /// DOKK's dock received the drag in flight (see `DockDragCoordinator.flixDropLanded`).
    func dockReceivedDrop(_ target: AnalyticsFlixDropTarget) {
        dockDropTarget = target
    }

    /// Sends `flix_drop` for an accepted drag out.
    private func reportDrop(_ items: [FlixItem], source: AnalyticsFlixDropSource,
                            place: (section: AnalyticsFlixSection, rank: Int?)?, at point: CGPoint,
                            front: FlixFrontmostContext?, plan: FlixDragPlan?, warning: FlixAnsweredWarning?,
                            predicted: Bool) {
        let landed = dockDropTarget
        dockDropTarget = nil
        let resolution = FlixDropTargetResolver.resolve(
            at: point, dockTarget: landed,
            front: front.map { ($0, contextServices?.fits.demand(for: $0)?.pageKind) })
        Analytics.track(.flixDrop(AnalyticsFlixDrop(
            items: items, source: source, place: place, target: resolution.target, targetCategory: resolution.category,
            pageKind: resolution.pageKind, plan: plan, warning: warning?.warning ?? .none,
            resolution: warning?.resolution, pinned: panelState.isPinned, predicted: predicted)))
    }

    /// A drag image that blurs an item the sensitive guard flagged, as its row and the tile do.
    func dragIcon(for item: FlixItem, base: NSImage) -> NSImage {
        guard settings.guardsSensitiveFiles, intelligence.annotations[item.id]?.isSensitive == true else { return base }
        return FlixSensitiveImage.blurred(base)
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
