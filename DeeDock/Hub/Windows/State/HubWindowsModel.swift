import AppKit
import Observation

/// State and intents for the Hub's Windows tab: every window of every running app, grouped by app.
///
/// Discovery reuses Radar's ``HarborWindowService`` through ``HubWindowsSource``. It runs only while
/// the tab is visible: ``hubTabDidAppear(shell:)`` starts it and installs workspace observers,
/// ``hubTabDidDisappear()`` cancels every task it owns and releases the service session. Main-actor isolated.
@MainActor @Observable
final class HubWindowsModel: HubTabModel {
    /// Where discovery stands.
    enum Phase: Equatable {
        /// Nothing gathered yet.
        case idle
        /// The first discovery is running; later refreshes keep showing the previous result.
        case loading
        case loaded
    }

    // MARK: HubTabModel

    var query = "" {
        didSet { if query != oldValue { refilter() } }
    }

    var searchPrompt: LocalizedStringResource { .hubWindowsSearchPrompt }

    // MARK: Observed state

    private(set) var phase: Phase = .idle
    /// Every group from the last discovery.
    private(set) var groups: [HubWindowGroup] = []
    /// Groups after the search query, in display order.
    private(set) var shownGroups: [HubWindowGroup] = []
    /// Permissions as of the last discovery. Assumed granted until a discovery says otherwise, so
    /// no hint flashes while the first pass runs.
    private(set) var access = HarborAccess(windows: true, thumbnails: true)
    /// App icons by app ID.
    private(set) var icons: [String: NSImage] = [:]
    /// Captured thumbnails by window-server number, which survives rediscovery.
    private(set) var thumbnails: [CGWindowID: CGImage] = [:]
    /// The keyboard-selected card's ``HubWindowItem/id``.
    var selection: String?
    /// Read when the tab appears; previews set it directly.
    private(set) var reduceMotion = false

    /// Windows shown after filtering.
    var windowCount: Int { shownGroups.reduce(0) { $0 + $1.windows.count } }
    /// Apps shown after filtering.
    var appCount: Int { shownGroups.count }

    // MARK: Dependencies and owned work

    @ObservationIgnored private let source: any HubWindowsSource
    @ObservationIgnored private let openRadarAction: @MainActor () -> Void
    @ObservationIgnored private let openAccessibilitySettingsAction: @MainActor () -> Void
    @ObservationIgnored private let openScreenRecordingSettingsAction: @MainActor () -> Void
    /// Valid between appear and disappear only.
    @ObservationIgnored private weak var shell: (any HubShell)?
    /// The running discovery. Replaced by each refresh and cancelled on disappear.
    @ObservationIgnored private var discovery: Task<Void, Never>?
    /// The debounce before a notification-driven refresh.
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    /// In-flight captures, at most ``thumbnailConcurrency``, keyed by window-server number.
    @ObservationIgnored private var captures: [CGWindowID: Task<Void, Never>] = [:]
    /// Captures waiting for a free slot, in display order.
    @ObservationIgnored private var captureQueue: [(number: CGWindowID, pixels: CGSize)] = []
    /// The last activation; the service session must outlive it so its window token stays valid.
    @ObservationIgnored private var activation: Task<Void, Never>?
    /// Bumped by every discovery and by disappear; results from an older generation are dropped.
    @ObservationIgnored private var generation = UUID()
    /// The service session holding the shown windows' handles.
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Card frames in ``HubWindowsView``'s grid coordinate space, written by the cards' geometry
    /// readers for up/down navigation. Not observed: frames never drive rendering.
    @ObservationIgnored var cardFrames: [String: CGRect] = [:]

    private static let thumbnailConcurrency = 3
    private static let refreshDelay: Duration = .milliseconds(350)

    /// - Parameters:
    ///   - openRadar: Opens Radar; the header's "Open Radar" button calls it.
    ///   - source: Discovery, capture, and activation. Nil uses Radar's live service.
    ///   - openAccessibilitySettings: Opens the Accessibility privacy pane from the hint.
    ///   - openScreenRecordingSettings: Opens the Screen Recording privacy pane from the hint.
    init(openRadar: @escaping @MainActor () -> Void,
         source: (any HubWindowsSource)? = nil,
         openAccessibilitySettings: @escaping @MainActor () -> Void = { SystemWindowAccessService().openSystemSettings() },
         openScreenRecordingSettings: @escaping @MainActor () -> Void = {
             SystemScreenCaptureAccessService().openSystemSettings()
         }) {
        openRadarAction = openRadar
        // Created here rather than as a default argument, which is evaluated outside the main actor.
        self.source = source ?? HarborHubWindowsSource()
        openAccessibilitySettingsAction = openAccessibilitySettings
        openScreenRecordingSettingsAction = openScreenRecordingSettings
    }

    // MARK: Lifecycle

    func hubTabDidAppear(shell: any HubShell) {
        self.shell = shell
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        selection = nil
        installObservers()
        refresh(recapture: true)
    }

    func hubTabDidDisappear() {
        removeObservers()
        pendingRefresh?.cancel()
        pendingRefresh = nil
        discovery?.cancel()
        discovery = nil
        cancelCaptures()
        generation = UUID()
        shell = nil
        guard let session = sessionID else { return }
        sessionID = nil
        // Keep the handles until a just-started activation has raised its window.
        let source = source, activation = activation
        Task {
            await activation?.value
            await source.end(session: session)
        }
    }

    // MARK: Intents

    func openRadar() {
        openRadarAction()
    }

    func openAccessibilitySettings() { openAccessibilitySettingsAction() }

    func openScreenRecordingSettings() { openScreenRecordingSettingsAction() }

    /// Brings the window forward (unminimizing or unhiding as needed) and closes an anchored Hub.
    func activate(_ item: HubWindowItem) {
        let window = item.window, source = source
        selection = item.id
        activation = Task { await source.activate(window) }
        Analytics.track(.hubWindowActivated(minimized: item.isMinimized))
        shell?.dismissAfterAction()
    }

    func handleKeyDown(_ event: NSEvent, fromSearchField: Bool) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        switch event.keyCode {
        case 123, 124:
            // In the search field, left and right move the text cursor.
            guard !fromSearchField, modifiers.isEmpty else { return false }
            moveSelection(event.keyCode == 123 ? .left : .right)
            return true
        case 125, 126:
            guard modifiers.isEmpty else { return false }
            moveSelection(event.keyCode == 125 ? .down : .up)
            if fromSearchField { shell?.focusContent() }
            return true
        case 36, 76:
            guard modifiers.isEmpty, let item = selectedItem ?? (query.isEmpty ? nil : orderedItems.first) else { return false }
            activate(item)
            return true
        default:
            // Typing while the cards have focus goes to the header search field. Option stays
            // allowed: many layouts type characters such as @ with it.
            guard !fromSearchField, modifiers.isDisjoint(with: [.command, .control]), let characters = event.characters, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0)
                      && $0.properties.generalCategory != .privateUse }) else { return false }
            query += characters
            shell?.focusSearchField()
            return true
        }
    }

    // MARK: Selection

    /// Shown cards in reading order.
    var orderedItems: [HubWindowItem] { shownGroups.flatMap(\.windows) }

    var selectedItem: HubWindowItem? {
        guard let selection else { return nil }
        return orderedItems.first { $0.id == selection }
    }

    func moveSelection(_ direction: HarborDirection) {
        selection = HubWindowsNavigation.next(from: selectedItem?.id, direction: direction,
                                              order: orderedItems.map(\.id), frames: cardFrames)
    }

    // MARK: Discovery

    /// Starts a discovery that replaces the shown groups when it finishes.
    /// - Parameter recapture: Captures every thumbnail again rather than only missing ones; set
    ///   when the tab appears, since windows may have changed while it was hidden.
    private func refresh(recapture: Bool) {
        discovery?.cancel()
        let generation = UUID()
        self.generation = generation
        if phase == .idle { phase = .loading }
        let source = source
        discovery = Task { [weak self] in
            let running = source.runningApps()
            let result = await source.discover(apps: running.map(\.app))
            guard let self, !Task.isCancelled, self.generation == generation else {
                // A newer discovery already replaced this session inside the service; this is a no-op then.
                await source.end(session: result.sessionID)
                return
            }
            self.apply(result, running: running, recapture: recapture)
        }
    }

    private func apply(_ discovery: HarborDiscovery, running: [HubRunningApp], recapture: Bool) {
        sessionID = discovery.sessionID
        access = discovery.access
        icons = Dictionary(running.map { ($0.app.id, $0.icon) }, uniquingKeysWith: { first, _ in first })
        groups = HubWindowsGrouping.groups(windows: discovery.windows, apps: running.map(\.app))
        let numbers = Set(groups.flatMap { $0.windows.compactMap(\.window.captureID) })
        thumbnails = thumbnails.filter { numbers.contains($0.key) }
        refilter()
        phase = .loaded
        scheduleCaptures(recapture: recapture)
    }

    private func refilter() {
        shownGroups = HubWindowsGrouping.filter(groups, query: query)
        if let selection, !orderedItems.contains(where: { $0.id == selection }) { self.selection = nil }
    }

    /// Debounces bursts of workspace notifications (an app launching posts several) into one discovery.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: Self.refreshDelay)
            guard !Task.isCancelled else { return }
            self?.refresh(recapture: false)
        }
    }

    // MARK: Thumbnails

    /// Queues captures for on-screen windows in display order. Runs after the cards are on screen,
    /// at most ``thumbnailConcurrency`` at a time on the service actor, never on the main path.
    private func scheduleCaptures(recapture: Bool) {
        cancelCaptures()
        guard access.thumbnails else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        captureQueue = groups.flatMap(\.windows).compactMap { item in
            guard let number = item.window.captureID, recapture || thumbnails[number] == nil else { return nil }
            return (number, Self.capturePixels(for: item.window.frame.size, scale: scale))
        }
        pumpCaptures()
    }

    private func pumpCaptures() {
        let source = source, generation = generation
        while captures.count < Self.thumbnailConcurrency, !captureQueue.isEmpty {
            let (number, pixels) = captureQueue.removeFirst()
            captures[number] = Task { [weak self] in
                let image = await source.thumbnail(number, fittingPixels: pixels)
                guard let self, !Task.isCancelled, self.generation == generation else { return }
                self.captures[number] = nil
                if let image { self.thumbnails[number] = image }
                self.pumpCaptures()
            }
        }
    }

    private func cancelCaptures() {
        captures.values.forEach { $0.cancel() }
        captures = [:]
        captureQueue = []
    }

    /// Pixel budget for a thumbnail that fills a card (with room for the hover lift) without
    /// upscaling, and never exceeds the window's own size.
    ///
    /// Cards crop to fill, so the shorter side relative to the card must cover it: the factor is
    /// the larger of the two axis ratios. The capture service then fits the window into this box.
    static func capturePixels(for windowSize: CGSize, scale: CGFloat) -> CGSize {
        let target = CGSize(width: HubWindowCardMetrics.thumbnailSize.width * 1.1,
                            height: HubWindowCardMetrics.thumbnailSize.height * 1.1)
        let width = max(windowSize.width, 1), height = max(windowSize.height, 1)
        let factor = min(max(target.width / width, target.height / height), 1)
        return CGSize(width: (width * factor * scale).rounded(.up), height: (height * factor * scale).rounded(.up))
    }

    // MARK: Observers

    /// App launch, quit, hide, and unhide change which windows exist; a Space switch changes which
    /// are on screen. A detached Hub also refreshes when another app activates, since it stays open
    /// while people work. Removed again in ``hubTabDidDisappear()``.
    private func installObservers() {
        removeObservers()
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [NSWorkspace.didLaunchApplicationNotification,
                                          NSWorkspace.didTerminateApplicationNotification,
                                          NSWorkspace.didHideApplicationNotification,
                                          NSWorkspace.didUnhideApplicationNotification,
                                          NSWorkspace.activeSpaceDidChangeNotification,
                                          NSWorkspace.didActivateApplicationNotification]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                let isActivation = note.name == NSWorkspace.didActivateApplicationNotification
                MainActor.assumeIsolated {
                    guard let self, pid != ProcessInfo.processInfo.processIdentifier else { return }
                    if isActivation, self.shell?.isDetached != true { return }
                    self.scheduleRefresh()
                }
            })
        }
    }

    private func removeObservers() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    #if DEBUG
    /// Fills the model with fixed content for previews; no discovery, observers, or permissions.
    func seedForPreview(running: [HubRunningApp], windows: [HarborWindow], access: HarborAccess,
                        thumbnails: [CGWindowID: CGImage] = [:], selection: String? = nil, query: String = "",
                        reduceMotion: Bool = false) {
        self.access = access
        self.thumbnails = thumbnails
        self.reduceMotion = reduceMotion
        icons = Dictionary(running.map { ($0.app.id, $0.icon) }, uniquingKeysWith: { first, _ in first })
        groups = HubWindowsGrouping.groups(windows: windows, apps: running.map(\.app))
        self.query = query
        refilter()
        self.selection = selection
        phase = .loaded
    }
    #endif
}
