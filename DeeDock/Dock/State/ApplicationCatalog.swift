import AppKit
import Observation

/// Application-wide workspace observation, icon cache, running order, and launch ownership.
///
/// `running` and `runningIDs` list regular application processes only; the Launcher, Hub,
/// suggestions, and Window Peek depend on that. Apps that macOS 27 reports as running in
/// background are published separately in `background`, and `dockOrderIDs` orders both
/// together for unpinned dock tiles.
@MainActor @Observable
final class ApplicationCatalog {
    let launcherLibrary: LauncherLibrary
    let launcherFavorites: LauncherFavorites
    let launcherHistory: LauncherHistory
    let suggestions: LauncherSuggestionsStore
    /// The App Recommendations survey, shared by every display's launcher.
    let suggestionSurvey: LauncherSuggestionSurvey
    @ObservationIgnored private lazy var suggestionObservation = LauncherSuggestionObservation(store: suggestions)
    private(set) var running: [ApplicationReference] = []
    private(set) var runningIDs: [String] = []
    /// Apps that are running in background, never including an app that is also in `running`.
    /// Empty when no monitor was injected or when the system's background state cannot be read.
    private(set) var background: [ApplicationReference] = []
    /// Running and background identities in the order unpinned dock tiles use.
    ///
    /// It is kept separately from `runningIDs` because an app keeps its entry while it moves
    /// between running and background, which is what keeps its tile in place, as in the system
    /// Dock. `runningIDs` drops the app as soon as its main process quits.
    private(set) var dockOrderIDs: [String] = []
    private(set) var launching: Set<String> = []
    /// Retained after completion so even a fast cold launch produces one complete visual cycle.
    private(set) var launchAnimationRequests: [String: Date] = [:]
    private(set) var documentRequests: [UUID: String] = [:]
    var busyApplications: Set<String> { launching.union(documentRequests.values) }
    let service: any ApplicationServicing
    @ObservationIgnored var didChange: (() -> Void)?
    @ObservationIgnored var activated: ((NSRunningApplication) -> Void)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var ownedWindowsObserver: NSObjectProtocol?
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var documentTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = UUID()
    /// Reads macOS 27's background state. Nil turns the feature off, as in tests and previews.
    @ObservationIgnored private let backgroundMonitor: BackgroundApplicationMonitor?
    /// Replaces the monitor's records; set only through `setBackgroundApplicationsForTesting`.
    @ObservationIgnored private var backgroundOverride: [BackgroundApplication]?
    /// The record behind each entry of `background`, by reference identity.
    @ObservationIgnored private var backgroundRecords: [String: BackgroundApplication] = [:]
    /// Holds back publishing while a quit is resolved; see `refreshAfterTermination()`.
    @ObservationIgnored private var terminationRefresh: Task<Void, Never>?
    @ObservationIgnored private var anotherTerminationPending = false

    init(service: any ApplicationServicing, launcherHistory: LauncherHistory? = nil, launcherLibrary: LauncherLibrary? = nil,
         suggestions: LauncherSuggestionsStore? = nil, launcherFavorites: LauncherFavorites? = nil,
         surveyDefaults: UserDefaults? = nil, backgroundMonitor: BackgroundApplicationMonitor? = nil) {
        self.launcherFavorites = launcherFavorites ?? LauncherFavorites(defaults: nil)
        self.service = service
        self.backgroundMonitor = backgroundMonitor
        self.launcherHistory = launcherHistory ?? LauncherHistory(defaults: nil)
        self.launcherLibrary = launcherLibrary ?? LauncherLibrary()
        let suggestions = suggestions ?? LauncherSuggestionsStore(directory: nil, defaults: nil)
        self.suggestions = suggestions
        suggestionSurvey = LauncherSuggestionSurvey(store: suggestions, analytics: .shared, defaults: surveyDefaults)
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    if notification.name == NSWorkspace.didTerminateApplicationNotification {
                        self?.refreshAfterTermination()
                    } else {
                        self?.refresh()
                    }
                    self?.suggestionObservation.workspaceEvent(notification)
                }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                             object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.suggestionObservation.activated(app)
                    self?.activated?(app)
                }
            }
        })
        ownedWindowsObserver = NotificationCenter.default.addObserver(
            forName: AppDockPresence.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        if let backgroundMonitor {
            backgroundMonitor.didChange = { [weak self] in self?.refresh() }
            backgroundMonitor.start()
        }
        refresh()
        suggestionObservation.start()
    }

    /// Publishes the current running and background applications.
    ///
    /// While a quit is being resolved this does nothing; the pending termination refresh
    /// publishes everything at once when it ends.
    func refresh() {
        guard terminationRefresh == nil else { return }
        publish()
    }

    private func publish() {
        let nextRunning = DockOrdering.unique(service.runningApplications())
        let nextIDs = DockOrdering.runningOrder(previous: runningIDs, current: nextRunning)
        let (nextBackground, records) = backgroundSnapshot(excluding: nextRunning)
        // A tile's identity survives running -> background -> running here, so it keeps its place.
        let nextDockIDs = DockOrdering.runningOrder(previous: dockOrderIDs, current: nextRunning + nextBackground)
        backgroundRecords = records
        // Unchanged arrays are not reassigned, so observers of the running set do not re-render.
        // `didChange` still fires: unhide and wake can change window occupancy without changing apps.
        if nextRunning != running { running = nextRunning }
        if nextIDs != runningIDs { runningIDs = nextIDs }
        if nextBackground != background { background = nextBackground }
        if nextDockIDs != dockOrderIDs { dockOrderIDs = nextDockIDs }
        didChange?()
    }

    /// Refreshes after an app quit, once the background state has caught up.
    ///
    /// The termination notification arrives before DOKK has read the app's background record.
    /// Publishing at once would drop an unpinned tile that is about to become a background
    /// tile, and the next read would bring it back: a visible flicker. Waiting for a read that
    /// starts after the quit, bounded by a short timeout, publishes both changes together.
    /// Every other refresh request in the meantime is folded into this one, because it would
    /// publish the same half-updated state. A further quit during the wait waits again, at
    /// most a few times so a burst of quits cannot hold the dock back for long.
    private func refreshAfterTermination() {
        guard let backgroundMonitor, backgroundMonitor.unavailability == nil else { return refresh() }
        guard terminationRefresh == nil else {
            anotherTerminationPending = true
            return
        }
        let currentGeneration = generation
        terminationRefresh = Task { [weak self, backgroundMonitor] in
            var waits = 0
            repeat {
                self?.anotherTerminationPending = false
                await backgroundMonitor.refreshAndWait(timeout: .milliseconds(250))
                waits += 1
            } while self?.anotherTerminationPending == true && waits < 4 && !Task.isCancelled
            guard let self, !Task.isCancelled, generation == currentGeneration else { return }
            terminationRefresh = nil
            anotherTerminationPending = false
            publish()
        }
    }

    /// Background apps as dock references, minus any app that also has a regular instance.
    private func backgroundSnapshot(excluding running: [ApplicationReference])
        -> ([ApplicationReference], [String: BackgroundApplication]) {
        let records = backgroundOverride
            ?? backgroundMonitor?.applications.values.sorted { $0.bundleURL.path < $1.bundleURL.path } ?? []
        guard !records.isEmpty else { return ([], [:]) }
        let runningIDs = Set(running.map(\.id))
        let runningURLs = Set(running.map(\.url.standardizedFileURL))
        var references: [ApplicationReference] = []
        var byID: [String: BackgroundApplication] = [:]
        for record in records {
            let reference = ApplicationReference(bundleIdentifier: record.bundleIdentifier, url: record.bundleURL,
                                                 name: record.name)
            guard !runningIDs.contains(reference.id), !runningURLs.contains(record.bundleURL),
                  byID[reference.id] == nil else { continue }
            references.append(reference)
            byID[reference.id] = record
        }
        return (references, byID)
    }

    /// Whether the app is currently published as running in background.
    func isRunningInBackground(_ reference: ApplicationReference) -> Bool {
        backgroundRecords[reference.id] != nil
    }

    /// Asks the monitor to end the app's remaining processes. Returns whether a stop was
    /// requested; false when the app is no longer running in background.
    ///
    /// The stop uses the record's bundle URL rather than the reference's, because a pinned
    /// reference can hold an older location. Failures are silent by design: the tile keeps
    /// its muted state until the processes actually exit.
    @discardableResult
    func stopRunningInBackground(_ reference: ApplicationReference) -> Bool {
        guard let backgroundMonitor, let record = backgroundRecords[reference.id] else { return false }
        backgroundMonitor.stopRunningInBackground(at: record.bundleURL)
        return true
    }

    /// Replaces the background records without a monitor and publishes. For tests only.
    func setBackgroundApplicationsForTesting(_ applications: [BackgroundApplication]) {
        backgroundOverride = applications
        refresh()
    }

    /// Owns app-icon toggle work so all display docks share duplicate suppression and teardown.
    /// Completion reports an error and whether the action opened the app, rather than hiding it.
    func performPrimaryAction(_ reference: ApplicationReference,
                              completion: @escaping (LocalizedStringResource?, Bool) -> Void) {
        submit(reference, operation: { service in try await service.performPrimaryAction(reference) == .opened }) { error in
            if error is ApplicationPrimaryActionError {
                completion(.errorHideApp(appName: reference.name), false)
            } else {
                completion(.errorOpenApp(appName: reference.name, details: error.localizedDescription), false)
            }
        } completion: { opened in
            completion(nil, opened)
        }
    }

    /// Only this catalog owns cancellation. The initiating dock supplies a weak, session-checked callback.
    func open(_ reference: ApplicationReference, ifCurrent: @escaping () -> Bool = { true },
              completion: @escaping (LocalizedStringResource?) -> Void) {
        submit(reference, ifCurrent: ifCurrent, operation: { service in try await service.open(reference); return true }) { error in
            completion(.errorOpenApp(appName: reference.name, details: error.localizedDescription))
        } completion: { _ in completion(nil) }
    }

    private func submit(_ reference: ApplicationReference, ifCurrent: @escaping () -> Bool = { true },
                        operation: @escaping (any ApplicationServicing) async throws -> Bool,
                        failure: @escaping (any Error) -> Void,
                        completion: @escaping (Bool) -> Void) {
        guard tasks[reference.id] == nil else { return }
        let currentGeneration = generation
        launching.insert(reference.id)
        tasks[reference.id] = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == currentGeneration { launching.remove(reference.id); tasks[reference.id] = nil }
            }
            do {
                try Task.checkCancellation()
                guard ifCurrent() else { return }
                let now = Date()
                launchAnimationRequests = launchAnimationRequests.filter { now.timeIntervalSince($0.value) < 30 }
                launchAnimationRequests[reference.id] = service.runningApplications().contains { $0.id == reference.id }
                    ? nil : now
                let opened = try await operation(service)
                guard !Task.isCancelled, generation == currentGeneration else { return }
                if opened { launcherHistory.record(reference) }
                completion(opened)
                refresh()
            } catch {
                guard !Task.isCancelled, generation == currentGeneration else { return }
                launchAnimationRequests[reference.id] = nil
                failure(error)
            }
        }
    }

    /// Uses the same Workspace opening path for running and closed apps. Workspace handles
    /// cooperative activation and reopening windows; a sent activation message alone does not.
    func springOpen(_ reference: ApplicationReference, isCurrent: @escaping () -> Bool,
                    completion: @escaping (LocalizedStringResource?) -> Void) {
        guard isCurrent() else { return }
        open(reference, ifCurrent: isCurrent) { error in
            guard isCurrent() else { return }
            completion(error)
        }
    }

    func pruneIcons(items: [DockItem], folders: [FolderDockItem] = []) {
        // `DockStore.refresh` just resolved these; resolving again would re-read every bookmark.
        let applicationURLs = items.compactMap(\.resolvedURL)
        let folderURLs = folders.compactMap { item -> URL? in
            let access = FolderResourceAccess(item.reference)
            defer { withExtendedLifetime(access) {} }
            return access.isAvailable ? access.url : nil
        }
        service.pruneIcons(keeping: Set(applicationURLs + folderURLs))
    }

    /// Every accepted batch owns a task and its file access, independent of launch suppression.
    /// Removing a panel invalidates only its callback; quitting cancels catalog-owned work.
    func openDocuments(_ documents: DocumentResourceAccess, with reference: ApplicationReference,
                       completion: @escaping (LocalizedStringResource?) -> Void) {
        let id = UUID()
        let currentGeneration = generation
        documentRequests[id] = reference.id
        documentTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                withExtendedLifetime(documents) {}
                if generation == currentGeneration {
                    documentRequests[id] = nil
                    documentTasks[id] = nil
                }
            }
            do {
                try Task.checkCancellation()
                try await service.openDocuments(documents.urls, with: reference)
                guard !Task.isCancelled, generation == currentGeneration else { return }
                launcherHistory.record(reference)
                completion(nil)
                refresh()
            } catch {
                guard !Task.isCancelled, generation == currentGeneration else { return }
                completion(.errorOpenDocuments(appName: reference.name, details: error.localizedDescription))
            }
        }
    }

    func stop() {
        suggestionObservation.stop()
        launcherLibrary.stop()
        generation = UUID()
        // Cancel first: stopping the monitor resumes the termination wait, which must then find
        // its task cancelled and publish nothing.
        terminationRefresh?.cancel()
        terminationRefresh = nil
        anotherTerminationPending = false
        backgroundMonitor?.didChange = nil
        backgroundMonitor?.stop()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        if let ownedWindowsObserver { NotificationCenter.default.removeObserver(ownedWindowsObserver) }
        ownedWindowsObserver = nil
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        documentTasks.values.forEach { $0.cancel() }
        documentTasks.removeAll()
        documentRequests.removeAll()
        launching.removeAll()
        launchAnimationRequests.removeAll()
        didChange = nil
        activated = nil
    }
}
