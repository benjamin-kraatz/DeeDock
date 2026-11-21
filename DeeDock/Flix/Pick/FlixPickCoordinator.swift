import AppKit
import ApplicationServices

/// Flix Pick: when another app shows an Open or Save picker, a slim rail beside it lists the files
/// (Open) or folders (Save) that app most likely wants. A click selects the row in the picker,
/// ⌥-click and double-click also press its default button, and a drag drops it in. The panel never
/// takes focus from the app (DEE-164, `docs/mockups/flix-pick.html`).
///
/// Owned by `FlixCoordinator` (``FlixCoordinator/pick``, set by `live()`), which calls
/// ``start(with:)``, ``apply(_:)`` on every settings change, and ``stop()``. It runs only while Flix
/// Files and **Flix Pick** are on, and stays silent without Accessibility permission, which it
/// never asks for. Apps in **Not in <App>** and DOKK itself are never observed.
///
/// Per picker: `FlixPickObserver` reports it (``FlixPickEvent``); the rows are built from Flix
/// Files' data (`FlixPickCandidates`) after the app's document types are read off the main actor;
/// files that are gone are dropped where the read policy lets DOKK look. A global mouse-down
/// monitor (location and click count only) runs while the picker is open, so its closing can be
/// told apart (`FlixPickClosing`); what was picked is learned into drag memory
/// (`FlixIntelligence.recordPickerPick`). The panel hides when the picker closes or loses focus,
/// its app moves to the back, the displays change, or the Mac sleeps.
///
/// Task ownership: at most one rows task (``rowsTask``) and one action (``actionTask``) at a time;
/// a new picker or a closed one cancels both. Main actor.
@MainActor
final class FlixPickCoordinator {
    private weak var flix: FlixCoordinator?
    private let observer = FlixPickObserver()
    let state = FlixPickState()
    private var panel: FlixPickPanelController?
    private var isActive = false

    /// The picker Flix Pick is following now.
    private struct Session {
        var picker: FlixPickPicker
        var bundleIdentifier: String
        var category: FlixAppCategory
        var evidence: FlixPickClosingEvidence
        /// The panel showed for this picker, so its closing is reported.
        var shown = false
    }

    private var session: Session?
    /// A picker that lost focus without closing, kept so it is recognized when focus returns.
    private var parked: Session?
    /// The action running on a row; a double-click on it upgrades it to a confirm.
    private struct Action {
        let row: FlixPickRow
        let rank: Int
        let kind: FlixPickPickerKind
        var trigger: FlixPickTrigger
        var confirm: Bool
        let started: ContinuousClock.Instant
        /// The route of the click a double-click completes, which already moved the picker.
        var earlierRoute: AnalyticsFlixPickRoute?
    }

    private var running: Action?
    /// A finished click's report, held for the double-click interval so a double-click reports once.
    private var heldReport: (action: Action, result: FlixPickActionResult, task: Task<Void, Never>)?
    private var rowsTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?
    private var types: [String: (open: FlixPickDocumentTypes, save: FlixPickDocumentTypes)] = [:]
    private var mouseMonitor: Any?
    private var systemObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var hovering = false
    private var menuOpen = false
    private var dragging = false

    init() {}

    // MARK: Lifecycle

    func start(with flix: FlixCoordinator) {
        self.flix = flix
        observer.event = { [weak self] event in self?.handle(event) }
        state.activate = { [weak self] row, trigger, confirm in self?.activate(row, trigger: trigger, confirm: confirm) }
        state.beginDrag = { [weak self] row, view, event in self?.beginDrag(row, view: view, event: event) }
        state.hoverChanged = { [weak self] inside in self?.hoverChanged(inside) }
        state.disableForApp = { [weak self] in self?.disableForCurrentApp() }
        state.prepareSettings = { [weak self] in
            self?.flix?.prepareSettings?()
            self?.hide()
        }
        state.menuTracking = { [weak self] open in
            self?.menuOpen = open
            if !open { self?.scheduleCollapse() }
        }
    }

    /// Starts or stops with the settings: Flix Files and Flix Pick on.
    func apply(_ settings: FlixSettings) {
        observer.excluded = Set(settings.flixPickExcludedApps)
        let active = settings.isEnabled && settings.showsFlixPick
        guard active != isActive else { return }
        isActive = active
        if active {
            observer.start()
            observeSystem()
        } else {
            deactivate()
        }
    }

    func stop() {
        deactivate()
        panel?.stop()
        panel = nil
        observer.event = nil
    }

    private func deactivate() {
        isActive = false
        observer.stop()
        endSession()
        parked = nil
        for entry in systemObservers { entry.center.removeObserver(entry.token) }
        systemObservers = []
        heldReport?.task.cancel()
        heldReport = nil
    }

    /// Displays changing and the Mac going to sleep hide the panel.
    private func observeSystem() {
        guard systemObservers.isEmpty else { return }
        let hide: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.hide() } }
        systemObservers.append((NotificationCenter.default, NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: hide)))
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            systemObservers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main, using: hide)))
        }
    }

    // MARK: Picker events

    private func handle(_ event: FlixPickEvent) {
        guard isActive else { return }
        switch event {
        case .appeared(let picker, let returning):
            appeared(picker, returning: returning)
        case .changed(let picker):
            guard session?.picker.serial == picker.serial else { return }
            session?.picker = picker
            state.buttonTitle = picker.buttonTitle
            panel?.follow(Self.appKit(picker.frame))
        case .selection(let serial, let url):
            guard session?.picker.serial == serial else { return }
            session?.evidence.selection = url
        case .folderChanged(let serial, let name):
            // The person moved a Save picker elsewhere: the folder Flix Pick put there no longer counts.
            guard session?.picker.serial == serial, running == nil, let placed = session?.evidence.placedByFlix,
                  name.map({ $0.localizedCaseInsensitiveCompare(Self.folderName(placed)) != .orderedSame }) ?? true
            else { return }
            session?.evidence.placedByFlix = nil
        case .closed(let serial, let destroyed):
            guard session?.picker.serial == serial else { return }
            closed(destroyed: destroyed)
        }
    }

    private func appeared(_ picker: FlixPickPicker, returning: Bool) {
        guard let flix, AXIsProcessTrusted(),
              let app = NSRunningApplication(processIdentifier: picker.processIdentifier),
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleIdentifier = app.bundleIdentifier,
              !flix.settings.flixPickExcludedApps.contains(bundleIdentifier) else { return }
        endSession()
        if returning, var restored = parked, restored.picker.serial == picker.serial {
            restored.picker = picker
            session = restored
        } else {
            session = Session(picker: picker, bundleIdentifier: bundleIdentifier,
                              category: FlixAppCategory.of(bundleIdentifier: bundleIdentifier, bundleURL: app.bundleURL),
                              evidence: FlixPickClosingEvidence(kind: picker.kind))
        }
        parked = nil
        installMouseMonitor()
        let appName = app.localizedName ?? bundleIdentifier
        let bundleURL = app.bundleURL
        let serial = picker.serial
        rowsTask = Task { [weak self] in
            guard let self else { return }
            let types = await documentTypes(bundleIdentifier, bundleURL: bundleURL)
            guard !Task.isCancelled, session?.picker.serial == serial, let flix = self.flix else { return }
            let candidates = FlixPickCandidates.rows(for: context(for: picker, appName: appName, bundleIdentifier: bundleIdentifier,
                                                                  types: picker.kind == .open ? types.open : types.save,
                                                                  flix: flix),
                                                     limit: FlixPickRanker.limit * 2)
            let missing = await Self.missing(candidates.map(\.path), policy: flix.readPolicy)
            guard !Task.isCancelled, session?.picker.serial == serial else { return }
            for path in missing { flix.intelligence.forgetPickerPick(path, app: bundleIdentifier) }
            let rows = Array(candidates.filter { !missing.contains($0.path) }.prefix(FlixPickRanker.limit))
            show(rows, appName: appName)
        }
    }

    private func context(for picker: FlixPickPicker, appName: String, bundleIdentifier: String,
                         types: FlixPickDocumentTypes, flix: FlixCoordinator) -> FlixPickContext {
        let intelligence = flix.intelligence
        let settings = flix.settings
        let sensitive = settings.guardsSensitiveFiles
            ? Set(intelligence.annotations.filter { $0.value.isSensitive }.keys) : []
        return FlixPickContext(kind: picker.kind, appName: appName, types: types, items: flix.history.items,
                               picks: intelligence.pickerPicks(for: bundleIdentifier),
                               dropCounts: intelligence.dropCounts(for: bundleIdentifier),
                               threads: settings.groupsThreads ? intelligence.threads : [],
                               sensitive: sensitive, hidesNoise: settings.hidesNoise, now: .now)
    }

    private func show(_ rows: [FlixPickRow], appName: String) {
        guard var current = session, let flix else { return }
        // Nothing likely: no panel, but the picker is still followed so a pick there is learned.
        guard !rows.isEmpty else { return }
        state.refreshAccessibilityOptions()
        state.kind = current.picker.kind
        state.appName = appName
        state.buttonTitle = current.picker.buttonTitle
        state.rows = rows
        state.now = .now
        state.policy = flix.readPolicy
        state.message = nil
        state.busyRowID = nil
        let panel = panel ?? makePanel()
        panel.show(beside: Self.appKit(current.picker.frame))
        if !current.shown {
            current.shown = true
            Analytics.track(.flixPickShown(picker: AnalyticsFlixPickerKind(current.picker.kind),
                                           appCategory: current.category, candidateCount: rows.count))
        }
        session = current
    }

    private func makePanel() -> FlixPickPanelController {
        let controller = FlixPickPanelController(state: state, content: FlixPickView(state: state))
        panel = controller
        return controller
    }

    /// The picker closed (`destroyed`) or only lost focus.
    private func closed(destroyed: Bool) {
        guard let current = session else { return }
        rowsTask?.cancel()
        actionTask?.cancel()
        panel?.hide()
        removeMouseMonitor()
        session = nil
        guard destroyed else {
            parked = current
            return
        }
        parked = nil
        let (outcome, chosen) = FlixPickClosing.outcome(current.evidence, closedAt: .now)
        if let chosen, outcome == .pickedViaFlixPick || outcome == .pickedElsewhere {
            flix?.intelligence.recordPickerPick(chosen, isFolder: current.picker.kind == .save,
                                                app: current.bundleIdentifier)
        }
        guard current.shown else { return }
        let rank = chosen.flatMap { path in state.rows.firstIndex { FlixPaths.standardized($0.path) == path } }
        Analytics.track(.flixPickPickerClosed(picker: AnalyticsFlixPickerKind(current.picker.kind), outcome: outcome,
                                              chosenRank: rank.map { $0 + 1 }))
    }

    private func endSession() {
        rowsTask?.cancel()
        rowsTask = nil
        actionTask?.cancel()
        actionTask = nil
        running = nil
        state.busyRowID = nil
        removeMouseMonitor()
        hide()
        session = nil
    }

    private func hide() {
        collapseTask?.cancel()
        hovering = false
        panel?.hide()
    }

    // MARK: Mouse presses on the picker

    /// Where the person presses the mouse while the picker is open: only the location, matched
    /// against the picker's own buttons and list, and the click count. Keys are never watched.
    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let clicks = event.clickCount
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated { self?.pressed(at: point, clickCount: clicks) }
        }
    }

    private func removeMouseMonitor() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    private func pressed(at point: CGPoint, clickCount: Int) {
        guard let picker = session?.picker else { return }
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        // AppKit (bottom-left, y up) to Accessibility (top-left, y down): only y flips.
        let target = picker.target(at: CGPoint(x: point.x, y: primaryMaxY - point.y))
        session?.evidence.lastPress = (target, clickCount, .now)
    }

    // MARK: Rows

    private func activate(_ row: FlixPickRow, trigger: FlixPickTrigger, confirm: Bool) {
        guard let current = session, panel?.isVisible == true else { return }
        if var action = running {
            // The second click of a double-click while the first click's jump still runs.
            guard action.row.id == row.id, confirm, !action.confirm else { return }
            action.confirm = true
            action.trigger = trigger
            running = action
            return
        }
        var started = ContinuousClock.now
        var trigger = trigger
        var earlierRoute: AnalyticsFlixPickRoute?
        if let held = heldReport {
            held.task.cancel()
            heldReport = nil
            if held.action.row.id == row.id, trigger == .doubleClick {
                // Reported once, as the double-click it became.
                started = held.action.started
                earlierRoute = held.result.route
            } else {
                report(held.action, held.result)
            }
        }
        if trigger == .doubleClick, !confirm { trigger = .click }
        let rank = (state.rows.firstIndex { $0.id == row.id } ?? 0) + 1
        let action = Action(row: row, rank: rank, kind: current.picker.kind, trigger: trigger, confirm: confirm,
                            started: started, earlierRoute: earlierRoute)
        running = action
        state.busyRowID = row.id
        setMessage(nil)
        let picker = current.picker
        let folderName = Self.folderName(row.path)
        actionTask = Task { [weak self] in
            guard let self else { return }
            let willConfirm: () -> Void = { [weak self] in self?.confirming(row.path, serial: picker.serial) }
            var result = await FlixPickRouter.perform(path: row.path, folderName: folderName, picker: picker,
                                                      confirm: confirm, observer: observer, willConfirm: willConfirm)
            // A double-click arrived while the click's jump ran: press the default button now.
            if !confirm, running?.confirm == true, result.selected, !Task.isCancelled {
                let second = await FlixPickRouter.perform(path: row.path, folderName: folderName, picker: picker,
                                                          confirm: true, observer: observer, willConfirm: willConfirm)
                result.confirmed = second.confirmed
                result.failure = second.failure
            }
            finish(running ?? action, result: result, serial: picker.serial)
        }
    }

    private func confirming(_ path: String, serial: Int) {
        guard session?.picker.serial == serial else { return }
        session?.evidence.confirmedByFlix = (FlixPaths.standardized(path), .now)
    }

    private func finish(_ action: Action, result: FlixPickActionResult, serial: Int) {
        if running?.row.id == action.row.id { running = nil }
        actionTask = nil
        if state.busyRowID == action.row.id { state.busyRowID = nil }
        if session?.picker.serial == serial {
            if result.selected {
                let path = FlixPaths.standardized(action.row.path)
                session?.evidence.placedByFlix = path
                // Setting the selection through Accessibility may not post a selection change.
                if action.kind == .open { session?.evidence.selection = URL(fileURLWithPath: path) }
            }
            if !result.selected, let failure = result.failure, failure != .pickerClosed {
                setMessage(String(localized: failure == .secureInput ? .flixPickFailedSecureInput : .flixPickFailed))
            }
        }
        // A plain click waits out the double-click interval, so a double-click reports once.
        if action.trigger == .click, !result.confirmed, result.selected {
            let task = Task { [weak self] in
                try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
                guard !Task.isCancelled, let self, let held = heldReport else { return }
                heldReport = nil
                report(held.action, held.result)
            }
            heldReport = (action, result, task)
        } else {
            report(action, result)
        }
        scheduleCollapse()
    }

    private func report(_ action: Action, _ result: FlixPickActionResult) {
        let duration = Int((ContinuousClock.now - action.started) / .milliseconds(1))
        let route = result.route == .alreadyThere ? action.earlierRoute ?? result.route : result.route
        Analytics.track(.flixPickUsed(AnalyticsFlixPickUse(
            picker: AnalyticsFlixPickerKind(action.kind), rank: action.rank, trigger: AnalyticsFlixPickTrigger(action.trigger),
            route: route, confirmed: result.confirmed, result: result.selected ? .selected : .failed,
            failure: result.failure, durationMs: max(0, duration))))
    }

    private func setMessage(_ message: String?) {
        messageTask?.cancel()
        state.message = message
        guard message != nil else { return }
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self else { return }
            state.message = nil
            scheduleCollapse()
        }
    }

    // MARK: Dragging a row in

    private func beginDrag(_ row: FlixPickRow, view: NSView, event: NSEvent) {
        guard let current = session, let flix else { return }
        let started = ContinuousClock.now
        let rank = (state.rows.firstIndex { $0.id == row.id } ?? 0) + 1
        let icon = FlixIconProvider.icon(for: row.item, policy: flix.readPolicy)
        dragging = FlixDragSession.begin(items: [row.item], icons: [row.item.id: icon], from: view, event: event,
                                         moved: { _ in },
                                         ended: { [weak self] accepted, point in
                                             self?.dragEnded(row, rank: rank, kind: current.picker.kind,
                                                             serial: current.picker.serial, accepted: accepted,
                                                             at: point, started: started)
                                         })
    }

    private func dragEnded(_ row: FlixPickRow, rank: Int, kind: FlixPickPickerKind, serial: Int, accepted: Bool,
                           at point: CGPoint, started: ContinuousClock.Instant) {
        dragging = false
        scheduleCollapse()
        guard accepted, let picker = session?.picker, picker.serial == serial,
              Self.appKit(picker.frame).contains(point) else { return }
        session?.evidence.placedByFlix = FlixPaths.standardized(row.path)
        let action = Action(row: row, rank: rank, kind: kind, trigger: .drag, confirm: false, started: started)
        report(action, FlixPickActionResult(route: .drag, selected: true))
    }

    // MARK: Hover and the menu

    private func hoverChanged(_ inside: Bool) {
        hovering = inside
        if inside {
            collapseTask?.cancel()
            panel?.setOpen(true)
        } else {
            scheduleCollapse()
        }
    }

    /// Closes the rail shortly after the pointer left, unless the menu, a drag, an action, or a
    /// note keeps it open.
    private func scheduleCollapse() {
        collapseTask?.cancel()
        guard !hovering else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, let self, !hovering, !menuOpen, !dragging, running == nil,
                  state.message == nil else { return }
            panel?.setOpen(false)
        }
    }

    private func disableForCurrentApp() {
        guard let current = session, let store = flix?.settingsStore else { return }
        Analytics.track(.flixPickDisabledForApp(appCategory: current.category))
        hide()
        if !store.settings.flixPickExcludedApps.contains(current.bundleIdentifier) {
            store.settings.flixPickExcludedApps.append(current.bundleIdentifier)
        }
    }

    // MARK: Helpers

    /// The app's declared types, read once per app and launch, off the main actor.
    private func documentTypes(_ bundleIdentifier: String, bundleURL: URL?)
        async -> (open: FlixPickDocumentTypes, save: FlixPickDocumentTypes) {
        if let known = types[bundleIdentifier] { return known }
        guard let bundleURL else { return (.anything, .anything) }
        let loaded = await Self.loadTypes(bundleURL)
        types[bundleIdentifier] = loaded
        return loaded
    }

    @concurrent nonisolated private static func loadTypes(_ url: URL)
        async -> (open: FlixPickDocumentTypes, save: FlixPickDocumentTypes) {
        FlixPickDocumentTypes.load(bundleURL: url)
    }

    /// The paths among `paths` that are gone. Only paths the read policy lets DOKK look at are
    /// checked, so no Files and Folders prompt can appear; the rest are kept. Off the main actor.
    @concurrent nonisolated private static func missing(_ paths: [String], policy: FlixReadPolicy) async -> Set<String> {
        var missing = Set<String>()
        for path in paths {
            guard let resolved = policy.resolve(path) else { continue }
            if !FileManager.default.fileExists(atPath: resolved) { missing.insert(path) }
        }
        return missing
    }

    /// An Accessibility frame in AppKit's screen space (see `FlixPickPlacement.appKitRect`).
    private static func appKit(_ rect: CGRect) -> CGRect {
        FlixPickPlacement.appKitRect(fromAX: rect, primaryMaxY: NSScreen.screens.first?.frame.maxY ?? 0)
    }

    private static func folderName(_ path: String) -> String {
        FlixPickCandidates.folderName(FlixPaths.standardized(path), home: NSHomeDirectory())
    }
}
