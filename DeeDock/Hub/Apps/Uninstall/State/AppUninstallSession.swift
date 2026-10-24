import Foundation
import Observation

/// One uninstall started from the Hub's Apps tab: what was found, what the user selected, and how
/// removal went.
///
/// ## Phases
/// ``Phase/scanning`` → ``Phase/review`` → ``Phase/working(_:)`` → ``Phase/done(_:)``. When nothing could
/// be removed (the password prompt was cancelled, the app didn't quit, macOS refused the bundle) the
/// session goes to ``Phase/stopped(_:)``, from which the user can try again.
///
/// ## Order of removal
/// 1. Quit the app and its helpers.
/// 2. Move the app bundle. A root-owned bundle goes to Finder together with every other selected item
///    that needs Finder, so one password prompt covers them and a cancelled prompt leaves everything in
///    place. A bundle DOKK may move goes through `NSWorkspace`, and to Finder only if macOS refuses
///    (App Management for another developer's app).
/// 3. Move the rest of the selection.
///
/// Data is never removed when the app itself couldn't be. Protected items (another app's container
/// without Full Disk Access) are never attempted.
///
/// ## Lifecycle
/// ``HubAppsModel`` owns the session while the sheet shows and calls ``cancel()`` when it goes away, which
/// stops inspecting, scanning, and measuring. Removal runs to completion once confirmed.
@MainActor @Observable
final class AppUninstallSession: Identifiable {
    enum Phase: Equatable {
        case scanning
        case review
        case working(Step)
        case stopped(Stop)
        case done(Summary)

        var isWorking: Bool { if case .working = self { true } else { false } }
    }

    enum Step: Equatable { case quitting, waitingForPassword, moving }

    /// Why nothing was removed.
    enum Stop: Equatable { case passwordCancelled, stillOpen, failed }

    /// What a finished uninstall did, for the done view.
    struct Summary: Equatable {
        /// Data items moved to the Trash, not counting the app.
        var movedItems: Int
        /// The app's and the moved items' size on disk, as far as it was measured.
        var bytes: Int64
        /// Selected items that are still there.
        var failedItems: Int
        /// Items that stayed because macOS privacy protection hid them.
        var protectedItems: Int
        var hasSystemExtensions: Bool
        /// A background helper or launchd job was moved; it runs until the next restart.
        var helpersKeepRunning: Bool
    }

    /// Progress of one item during removal.
    enum ItemProgress: Equatable { case working, moved, failed }

    /// Where the Full Disk Access card is.
    enum AccessStage: Equatable {
        case idle
        /// The user opened System Settings; the card now offers to relaunch DOKK.
        case openedSettings
    }

    let id = UUID()
    let appURL: URL
    let appName: String
    /// The app's identity in DOKK (pins, favorites).
    let applicationID: String
    /// Displays whose dock pins the app.
    let pinnedDisplayCount: Int

    private(set) var target: AppUninstallTarget?
    /// Everything found, in the scanner's order.
    private(set) var leftovers: [AppLeftover] = []
    private(set) var measures: [String: AppLeftoverMeasure] = [:]
    private(set) var appSize: AppLeftoverMeasure = .measuring
    private(set) var selection: Set<String> = []
    private(set) var phase: Phase = .scanning
    private(set) var appProgress: ItemProgress?
    private(set) var itemProgress: [String: ItemProgress] = [:]
    private(set) var accessStage: AccessStage = .idle
    private(set) var isRunning: Bool
    /// Unpin the app from every connected display's dock after removing it.
    var unpin: Bool
    var relatedExpanded = false

    /// Called with each new phase; the owner keeps the Hub open while removal works.
    @ObservationIgnored var onPhaseChange: ((Phase) -> Void)?
    /// Called once the app is in the Trash, before the done view shows: unpin, forget, refresh.
    @ObservationIgnored var didRemoveApp: ((AppUninstallSession) -> Void)?

    @ObservationIgnored private let services: AppUninstallServices
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var cancellers: [@Sendable () -> Void] = []
    @ObservationIgnored private var lastStop: Stop?
    @ObservationIgnored private var usedFinder = false
    @ObservationIgnored private var reported = false

    /// Starts inspecting and scanning the app at once.
    /// - Parameters:
    ///   - application: The app to uninstall.
    ///   - pinnedDisplayCount: How many displays pin it.
    ///   - services: ``AppUninstallServices/live(installed:)`` outside previews.
    init(application: ApplicationReference, pinnedDisplayCount: Int, services: AppUninstallServices) {
        appURL = application.url.standardizedFileURL
        appName = application.name
        applicationID = application.id
        self.pinnedDisplayCount = pinnedDisplayCount
        self.services = services
        unpin = pinnedDisplayCount > 0
        isRunning = services.isRunning(appURL)
        start()
    }

    /// A session frozen in one state, for previews. Nothing runs.
    init(preview target: AppUninstallTarget, leftovers: [AppLeftover], measures: [String: AppLeftoverMeasure],
         phase: Phase, pinnedDisplayCount: Int = 0, isRunning: Bool = false, accessStage: AccessStage = .idle,
         itemProgress: [String: ItemProgress] = [:], appProgress: ItemProgress? = nil) {
        appURL = target.url
        appName = target.name
        applicationID = target.bundleIdentifier ?? target.url.path
        self.pinnedDisplayCount = pinnedDisplayCount
        services = .inert
        unpin = pinnedDisplayCount > 0
        self.isRunning = isRunning
        self.target = target
        self.leftovers = leftovers
        self.measures = measures
        appSize = target.byteCount.map(AppLeftoverMeasure.size) ?? .measuring
        selection = Set(leftovers.filter(\.selectedByDefault).map(\.id))
        self.phase = phase
        self.accessStage = accessStage
        self.itemProgress = itemProgress
        self.appProgress = appProgress
        reported = true
    }

    // MARK: Derived state

    /// The app's own data, for the App data section.
    var dataItems: [AppLeftover] { leftovers.filter { $0.match != .similarName } }
    /// Name-only matches, for "Possibly related".
    var relatedItems: [AppLeftover] { leftovers.filter { $0.match == .similarName } }
    /// Items of the app's own data that macOS hides without Full Disk Access.
    var protectedCount: Int { dataItems.filter(\.isProtected).count }
    /// Selected items DOKK will try to move.
    var selectedItems: [AppLeftover] { leftovers.filter { selection.contains($0.id) && !$0.isProtected } }
    /// Whether the user may still change the selection.
    var isEditable: Bool { phase == .review || { if case .stopped = phase { true } else { false } }() }
    var canConfirm: Bool { isEditable }

    /// The app and the selected items' known size.
    var selectedBytes: Int64 {
        selectedItems.reduce(Self.bytes(appSize)) { $0 + Self.bytes(measures[$1.id]) }
    }

    /// Whether a size is still being measured, so totals are lower bounds.
    var isMeasuring: Bool {
        appSize == .measuring || selectedItems.contains { measures[$0.id] == .measuring }
    }

    /// Removing the selection asks for the user's password: the app or a selected item is root-owned.
    var needsPassword: Bool {
        target?.ownedByRoot == true || selectedItems.contains { $0.domain == .allUsers }
    }

    func isSelected(_ item: AppLeftover) -> Bool { selection.contains(item.id) }

    // MARK: Actions

    func setSelected(_ selected: Bool, _ item: AppLeftover) {
        guard isEditable, !item.isProtected else { return }
        if selected { selection.insert(item.id) } else { selection.remove(item.id) }
    }

    /// Opens the Full Disk Access pane, after which the card offers to relaunch DOKK.
    func openAccessSettings() {
        services.openAccessSettings()
        accessStage = .openedSettings
    }

    /// Relaunches DOKK so a Full Disk Access grant applies; the sheet reopens for this app afterward.
    func relaunch() {
        report(.relaunched)
        if !services.relaunch(appURL) { reported = false }
    }

    /// Starts removal of the app and the selection.
    func confirm() {
        guard canConfirm, target != nil else { return }
        tasks.append(Task { [weak self] in await self?.remove() })
    }

    /// Stops background work; removal already confirmed runs on. Reports the outcome if the session ends
    /// without finishing.
    func cancel() {
        for canceller in cancellers { canceller() }
        cancellers = []
        if !phase.isWorking { for task in tasks { task.cancel() } }
        if case .done = phase { return }
        report(lastStop.map(AnalyticsUninstallOutcome.init) ?? .dismissed)
    }

    // MARK: Scanning

    private func start() {
        let url = appURL, name = appName
        let inspect = services.inspect, scan = services.scan
        tasks.append(Task { [weak self] in
            let inspection = Task.detached(priority: .userInitiated) { inspect(url, name) }
            self?.cancellers.append { inspection.cancel() }
            let target = await inspection.value
            guard let self, !Task.isCancelled else { return }
            self.target = target
            if let bytes = target.byteCount { appSize = .size(bytes) }
            let scanning = Task.detached(priority: .userInitiated) { scan(target) }
            cancellers.append { scanning.cancel() }
            let found = await scanning.value
            guard !Task.isCancelled else { return }
            leftovers = found
            selection = Set(found.filter(\.selectedByDefault).map(\.id))
            for item in found where !item.isProtected { measures[item.id] = .measuring }
            setPhase(.review)
            measure(found.filter { !$0.isProtected }, includingApp: target.byteCount == nil)
        })
    }

    /// Measures one item after another off the main actor, publishing each size as it arrives.
    private func measure(_ items: [AppLeftover], includingApp: Bool) {
        let measure = services.measure, appURL = appURL
        let work = Task.detached(priority: .utility) { [weak self] in
            if includingApp {
                let size = measure(appURL)
                await self?.setAppSize(size)
            }
            for item in items {
                if Task.isCancelled { return }
                let size = measure(item.url)
                await self?.setMeasure(size, for: item.id)
            }
        }
        cancellers.append { work.cancel() }
    }

    private func setMeasure(_ measure: AppLeftoverMeasure, for id: String) { measures[id] = measure }
    private func setAppSize(_ measure: AppLeftoverMeasure) { appSize = measure }

    // MARK: Removal

    private func remove() async {
        guard let target else { return }
        itemProgress = [:]
        appProgress = nil
        if services.isRunning(appURL) {
            setPhase(.working(.quitting))
            appProgress = .working
            guard await services.quit(appURL) else { return stop(.stillOpen) }
            isRunning = false
        }
        let appPresent = services.exists(appURL)
        if appPresent, !AppUninstallPathPolicy.allowsApp(appURL) { return stop(.failed) }
        let selected = selectedItems
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Items the policy refuses stay out of the Finder request; the loop below marks them not moved.
        let viaFinder = Set(selected.filter {
            services.needsFinder($0.url) && AppUninstallPathPolicy.allowsData($0.url, home: home)
        }.map(\.id))
        // Finder fails the whole request when one path is missing, so only send what's still there.
        let finderData = selected.filter { viaFinder.contains($0.id) && services.exists($0.url) }

        if appPresent, target.ownedByRoot || services.needsFinder(appURL) {
            // One request for everything Finder must move, so one password prompt covers it all.
            setPhase(.working(.waitingForPassword))
            appProgress = .working
            for item in finderData { itemProgress[item.id] = .working }
            usedFinder = true
            let outcome = await services.finderTrash([appURL] + finderData.map(\.url))
            guard !services.exists(appURL) else {
                itemProgress = [:]
                return stop(outcome == .cancelled ? .passwordCancelled : .failed)
            }
            appProgress = .moved
            for item in finderData { itemProgress[item.id] = services.exists(item.url) ? .failed : .moved }
        } else {
            setPhase(.working(.moving))
            appProgress = .working
            if appPresent, await services.recycle(appURL) != .moved {
                // App Management keeps DOKK from moving another developer's app; Finder may.
                usedFinder = true
                let outcome = await services.finderTrash([appURL])
                guard !services.exists(appURL) else { return stop(outcome == .cancelled ? .passwordCancelled : .failed) }
            }
            appProgress = .moved
            if !finderData.isEmpty {
                setPhase(.working(.waitingForPassword))
                for item in finderData { itemProgress[item.id] = .working }
                usedFinder = true
                _ = await services.finderTrash(finderData.map(\.url))
                for item in finderData { itemProgress[item.id] = services.exists(item.url) ? .failed : .moved }
            }
        }

        setPhase(.working(.moving))
        for item in selected where !viaFinder.contains(item.id) {
            guard AppUninstallPathPolicy.allowsData(item.url, home: home) else {
                itemProgress[item.id] = .failed
                continue
            }
            itemProgress[item.id] = .working
            itemProgress[item.id] = await services.recycle(item.url) == .moved ? .moved : .failed
        }

        didRemoveApp?(self)
        let moved = selected.filter { itemProgress[$0.id] == .moved }
        let summary = Summary(
            movedItems: moved.count,
            bytes: moved.reduce(Self.bytes(appSize)) { $0 + Self.bytes(measures[$1.id]) },
            failedItems: selected.count - moved.count, protectedItems: protectedCount,
            hasSystemExtensions: target.hasSystemExtensions, helpersKeepRunning: moved.contains(where: \.keepsRunning))
        setPhase(.done(summary))
        report(summary.failedItems == 0 ? .completed : .partial)
    }

    private func stop(_ reason: Stop) {
        appProgress = nil
        lastStop = reason
        setPhase(.stopped(reason))
    }

    private func setPhase(_ phase: Phase) {
        self.phase = phase
        onPhaseChange?(phase)
    }

    // MARK: Analytics

    private func report(_ outcome: AnalyticsUninstallOutcome) {
        guard !reported else { return }
        reported = true
        Analytics.track(.hubAppUninstall(
            outcome: outcome, source: AnalyticsUninstallSource(target?.source), dataCount: dataItems.count,
            selectedCount: selectedItems.count,
            movedCount: itemProgress.values.filter { $0 == .moved }.count,
            protectedCount: protectedCount,
            relatedSelected: selectedItems.filter { $0.match == .similarName }.count,
            usedFinder: usedFinder, unpinned: unpin && pinnedDisplayCount > 0 && outcome.removedApp))
    }

    private static func bytes(_ measure: AppLeftoverMeasure?) -> Int64 {
        if case .size(let bytes) = measure { bytes } else { 0 }
    }
}
