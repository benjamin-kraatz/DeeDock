import Foundation
import Observation

/// Count-only usage events from the state machine. The production sink forwards them to
/// ``Analytics``; turning Vapor on or off is reported by ``VaporCoordinator``.
nonisolated enum VaporAnalyticsEvent: Equatable, Sendable {
    case foldersAdded(source: VaporAddSource, count: Int)
    case deleted(count: Int, bytes: Int64)
    case undone(count: Int)
}

/// Vapor's state machine: the folders in the orb, measuring, Finder suggestions, the hold to
/// delete, staging, the undo window and the freed capsule.
///
/// It owns no windows and reads no live workspace state, so it runs in tests with fakes. The
/// ``VaporCoordinator`` feeds it Finder results and presentation inputs (lighting, drag
/// proximity, orb motion) and shows windows from its state. Views only read this object and
/// call its intent methods.
///
/// Main-actor isolated. Every task it starts is stored and cancelled by ``stop()``, except the
/// background removal of already staged folders, which must finish.
@MainActor @Observable
final class VaporController {
    /// Everything the controller needs from outside, injectable for tests.
    struct Dependencies {
        var store: VaporStore
        var home: URL
        var policy: VaporDropPolicy
        var measurer: any VaporMeasuring
        var deleter: any VaporDeleting
        var now: () -> Date = Date.init
        var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
        var analytics: (VaporAnalyticsEvent) -> Void = { _ in }
    }

    /// How long Undo stays available after a delete.
    static let undoWindow: Duration = .seconds(5)
    /// How long "Freed …" stays before the capsule goes away.
    static let freedDuration: Duration = .seconds(2.2)
    /// How long "Put back …" stays after Undo.
    static let restoredDuration: Duration = .seconds(1.6)
    /// How long a failure or "couldn't be restored" capsule stays.
    static let noticeDuration: Duration = .seconds(4)
    /// How long a refusal message stays above the orb.
    static let refusalDuration: Duration = .seconds(2.5)

    // MARK: State

    /// The folders in the orb, oldest first.
    private(set) var folders: [VaporFolder] = []
    /// The capsule above the orb, or nil.
    private(set) var status: VaporStatus?
    /// True from the end of the hold until every folder has been renamed or failed.
    private(set) var isStaging = false
    private(set) var isPanelOpen = false
    /// The Hold to Delete button's fill. Views sample it with `progress(at:)`.
    private(set) var hold = VaporHoldProgress()
    /// The last refused drop: shake the orb red and show the message. Clears itself after
    /// ``refusalDuration``; a new refusal gets a new token.
    private(set) var refusal: VaporEvent<VaporRefusal>?
    /// The last folders added: pop them in at the top and squash the orb.
    private(set) var addition: VaporEvent<VaporAddition>?
    /// The last delete: pull the rows into the orb and evaporate.
    private(set) var deletion: VaporEvent<VaporDeletion>?
    /// "Delete All…" from the orb's menu: the panel opens and the delete button nudges.
    private(set) var deleteNudge: VaporEvent<Int>?
    /// The folder in Finder's front window while Finder is frontmost, or nil.
    private(set) var finderFolder: URL?
    /// Every suggested child of ``finderFolder``, before removing what's in the orb.
    private(set) var finderItems: [VaporSuggestion] = []
    /// The Finder folder whose suggestions the person dismissed with ×.
    private(set) var dismissedFinderFolder: URL?
    /// Whether DOKK may ask Finder for its front folder.
    var automationPermission: VaporAutomationPermission = .unavailable
    /// The bubble under the pointer; the capsule shows its name and tag instead of the count.
    var hoveredSuggestionID: String?

    // Presentation inputs, set by the coordinator and read by views.

    /// Proximity of an in-flight file drag to the orb and whether it's over the panel.
    var dropHover = VaporDropHover.none
    /// The orb's velocity and acceleration while being dragged, for the slosh.
    var orbMotion = VaporOrbMotion.still
    /// Lighting from the orb's display's lamp.
    var lighting = VaporLighting.overhead
    /// The pointer is over the orb, so the callout shows the tooltip.
    var isOrbHovered = false
    /// The top corner that holds the count badge.
    var badgeCorner = VaporBadgeCorner.topLeading
    /// The panel and bubbles open toward the left (the orb is on the display's right half).
    var opensLeft = false
    var reduceMotion = false
    var reduceTransparency = false
    /// Whether the orb is on screen and which show or hide animation it plays. While it is
    /// leaving, the bubbles and the capsule are hidden and the panel can't open.
    private(set) var orbPresence = VaporOrbPresence()

    // MARK: Callbacks

    /// Asks Finder for Automation permission. Set by the coordinator; the panel's Turn On calls it.
    @ObservationIgnored var requestFinderAccess: (() -> Void)?

    // MARK: Private

    private struct PendingBatch {
        let items: [(folder: VaporFolder, entry: VaporLedgerEntry)]
        let failed: Int
        var entries: [VaporLedgerEntry] { items.map(\.entry) }
        var bytes: Int64 { items.reduce(0) { $0 + $1.entry.bytes } }
    }

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var pending: PendingBatch?
    @ObservationIgnored private var hasRestored = false
    @ObservationIgnored private var measureTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var refusalTask: Task<Void, Never>?
    /// Background removals still running. They are not cancelled: staged folders must go.
    @ObservationIgnored private(set) var removalTasks: [Task<Void, Never>] = []

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var home: URL { dependencies.home }

    // MARK: Derived state

    var totals: VaporTotals { VaporTotals(folders) }

    /// Folders matching no rule. The panel warns before deleting them.
    var unknownCount: Int { folders.filter { !$0.classification.isKnown }.count }

    /// Suggestions from the Finder folder, minus anything in the orb, inside a folder in the
    /// orb, or staged for deletion. Empty while dismissed.
    var suggestions: [VaporSuggestion] {
        guard let finderFolder, finderFolder != dismissedFinderFolder else { return [] }
        let taken = folders.map(\.url) + (pending?.items.map(\.folder.url) ?? [])
        return finderItems.filter { item in
            !taken.contains { item.url.isSameOrDescendant(of: $0, resolvingSymlinks: false) }
        }
    }

    /// The bubbles beside the orb: up to five suggestions, hidden while the panel is open.
    var bubbleSuggestions: [VaporSuggestion] {
        isPanelOpen || !orbPresence.isShown ? [] : Array(suggestions.prefix(VaporGeometry.maxBubbles))
    }

    /// The panel's "Show caches from the open Finder folder · Turn On" line is visible.
    var offersFinderAccess: Bool { automationPermission == .undetermined }

    /// What the small capsule above the orb shows, in priority order: a refusal, the delete
    /// status, "Drop to add" while a drag is over the orb, then the hover tooltip.
    var callout: VaporCallout? {
        guard orbPresence.isShown else { return nil }
        if let refusal { return .refusal(refusal.payload) }
        if let status { return .status(status) }
        if dropHover.proximity.isOverOrb { return .dropToAdd }
        if isOrbHovered, !isPanelOpen { return .tooltip(totals) }
        return nil
    }

    /// The Undo deadline while the undo window is open.
    var undoDeadline: Date? {
        if case .deleted(_, _, let deadline) = status?.kind { return deadline }
        return nil
    }

    // MARK: Lifecycle

    /// Shows Vapor's state again. The first call puts back the folders saved at the last quit,
    /// dropping paths that are missing or no longer acceptable; later calls resume measuring
    /// folders whose size was still pending when Vapor was turned off.
    func start() {
        if !hasRestored {
            hasRestored = true
            let urls = dependencies.store.state.folderPaths.map { URL(fileURLWithPath: $0) }
            apply(urls, source: .restore, announce: false)
            return
        }
        for folder in folders where folder.measurement.isPending && measureTasks[folder.id] == nil {
            measure(folder)
        }
    }

    /// Cancels timers and measurements and closes the panel; the folders stay. A pending undo
    /// window is committed first, so staged folders are always removed, never left behind or
    /// silently restored.
    func stop() {
        commitPending(showFreed: false)
        isPanelOpen = false
        hold.reset()
        holdTask?.cancel()
        holdTask = nil
        statusTask?.cancel()
        statusTask = nil
        status = nil
        refusalTask?.cancel()
        refusalTask = nil
        refusal = nil
        measureTasks.values.forEach { $0.cancel() }
        measureTasks.removeAll()
        isOrbHovered = false
        dropHover = .none
        orbMotion = .still
        clearFinderFolder()
    }

    /// Vapor was turned on: the orb is on screen. `animated` condenses it out of particles;
    /// otherwise it is simply there (launch).
    func showOrb(animated: Bool) {
        orbPresence = VaporOrbPresence(isShown: true, token: animated ? UUID() : nil)
    }

    /// Vapor was turned off: the panel closes, the bubbles and the capsule go, and the orb
    /// shrinks away. The coordinator calls ``stop()`` once it has.
    func hideOrb() {
        closePanel()
        isOrbHovered = false
        dropHover = .none
        hoveredSuggestionID = nil
        orbPresence = VaporOrbPresence(isShown: false, token: UUID())
    }

    // MARK: Adding and removing

    /// Whether a drag carrying `urls` would add anything. Used to accept or refuse a drag early.
    func canAccept(_ urls: [URL]) -> Bool {
        dependencies.policy.evaluate(urls, existing: folders.map(\.url)).contains {
            if case .accept = $0 { return true }
            return false
        }
    }

    /// Adds dropped or suggested folders. Refusals raise ``refusal`` (the first one, once).
    /// - Returns: Whether at least one folder was added.
    @discardableResult
    func add(_ urls: [URL], source: VaporAddSource) -> Bool {
        apply(urls, source: source, announce: true)
    }

    @discardableResult
    private func apply(_ urls: [URL], source: VaporAddSource, announce: Bool) -> Bool {
        let decisions = dependencies.policy.evaluate(urls, existing: folders.map(\.url))
        var added: [VaporFolder] = []
        var firstRefusal: VaporRefusal?
        for decision in decisions {
            switch decision {
            case .refuse(let reason):
                if firstRefusal == nil { firstRefusal = reason }
            case .accept(let url, let replacing):
                for replaced in replacing { removeFolder(at: replaced) }
                added.removeAll { replacing.contains($0.url) }
                let folder = VaporFolder(url: url, classification: VaporClassifier.classify(url, home: dependencies.home))
                folders.append(folder)
                added.append(folder)
                measure(folder)
            }
        }
        if announce, let firstRefusal { refuse(firstRefusal) }
        guard !added.isEmpty else { return false }
        persistFolders()
        if announce {
            addition = VaporEvent(VaporAddition(folderIDs: added.map(\.id), source: source))
            if source != .restore { dependencies.analytics(.foldersAdded(source: source, count: added.count)) }
        }
        return true
    }

    /// Takes one folder out of the orb without deleting it.
    func remove(_ id: VaporFolder.ID) {
        guard let folder = folders.first(where: { $0.id == id }) else { return }
        removeFolder(at: folder.url)
        persistFolders()
        if folders.isEmpty { releaseHoldImmediately() }
    }

    /// Takes everything out of the orb without deleting anything.
    func clear() {
        guard !folders.isEmpty else { return }
        measureTasks.values.forEach { $0.cancel() }
        measureTasks.removeAll()
        folders.removeAll()
        persistFolders()
        releaseHoldImmediately()
    }

    private func refuse(_ reason: VaporRefusal) {
        let event = VaporEvent(reason)
        refusal = event
        refusalTask?.cancel()
        let sleep = dependencies.sleep
        refusalTask = Task { [weak self] in
            do { try await sleep(Self.refusalDuration) } catch { return }
            guard let self, self.refusal?.token == event.token else { return }
            self.refusal = nil
        }
    }

    private func removeFolder(at url: URL) {
        guard let index = folders.firstIndex(where: { $0.url == url }) else { return }
        let id = folders[index].id
        measureTasks.removeValue(forKey: id)?.cancel()
        folders.remove(at: index)
    }

    private func persistFolders() {
        dependencies.store.setFolders(folders.map(\.url))
    }

    // MARK: Measuring

    private func measure(_ folder: VaporFolder) {
        let measurer = dependencies.measurer
        let url = folder.url, id = folder.id
        measureTasks[id]?.cancel()
        measureTasks[id] = Task { [weak self] in
            let result = await measurer.measure(url)
            guard !Task.isCancelled, let self else { return }
            self.measureTasks[id] = nil
            guard result != .pending, let index = self.folders.firstIndex(where: { $0.id == id }) else { return }
            self.folders[index].measurement = result
        }
    }

    // MARK: Panel

    func openPanel() {
        guard !isPanelOpen, orbPresence.isShown else { return }
        isPanelOpen = true
        hoveredSuggestionID = nil
    }

    func closePanel() {
        guard isPanelOpen else { return }
        isPanelOpen = false
        releaseHoldImmediately()
    }

    func togglePanel() {
        isPanelOpen ? closePanel() : openPanel()
    }

    /// "Delete All…" from the orb's menu: opens the panel and nudges the delete button.
    func nudgeDelete() {
        openPanel()
        guard !folders.isEmpty else { return }
        deleteNudge = VaporEvent(folders.count)
    }

    // MARK: Hold to delete

    /// The delete button was pressed. Completing the 0.9 s hold deletes everything.
    func pressHold() {
        guard !folders.isEmpty, !isStaging else { return }
        let now = dependencies.now()
        hold.press(at: now)
        holdTask?.cancel()
        let remaining = hold.remainingHold(at: now)
        let sleep = dependencies.sleep
        holdTask = Task { [weak self] in
            try? await sleep(.seconds(remaining))
            guard !Task.isCancelled, let self else { return }
            self.holdTask = nil
            self.hold.reset()
            self.deleteAll()
        }
    }

    /// The delete button was released before the hold finished: the fill drains back.
    func releaseHold() {
        holdTask?.cancel()
        holdTask = nil
        hold.release(at: dependencies.now())
    }

    private func releaseHoldImmediately() {
        holdTask?.cancel()
        holdTask = nil
        hold.reset()
    }

    // MARK: Deleting

    /// Stages every folder in the orb and opens the undo window. VoiceOver's action calls this
    /// directly, since holding isn't practical there.
    /// - Returns: The staging task, for tests to await. Nil when there was nothing to do.
    @discardableResult
    func deleteAll() -> Task<Void, Never>? {
        guard !isStaging, !folders.isEmpty else { return nil }
        // A second delete during an undo window commits the first one.
        commitPending(showFreed: false)
        releaseHoldImmediately()
        statusTask?.cancel()
        statusTask = nil
        for index in folders.indices { folders[index].failure = nil }
        // Check every folder again first: since it was added it may have become a link, or now
        // resolve into a protected location. Those stay in the orb, untouched, with a reason.
        let policy = dependencies.policy
        var refused: [VaporStageOutcome] = []
        let targets = folders.filter { folder in
            switch policy.revalidate(folder.url) {
            case nil: return true
            case .missing: refused.append(.failed(folderID: folder.id, .missing))
            case .some: refused.append(.failed(folderID: folder.id, .changed))
            }
            return false
        }
        isStaging = true
        if !targets.isEmpty {
            deletion = VaporEvent(VaporDeletion(folders: targets, fromPanel: isPanelOpen))
            isPanelOpen = false
        }
        let requests = targets.map { VaporStageRequest(folderID: $0.id, url: $0.url, bytes: $0.measurement.bytes) }
        let deleter = dependencies.deleter
        return Task { [weak self] in
            let outcomes = requests.isEmpty ? [] : await deleter.stage(requests)
            self?.finishStaging(refused + outcomes, targets: targets)
        }
    }

    private func finishStaging(_ outcomes: [VaporStageOutcome], targets: [VaporFolder]) {
        isStaging = false
        var staged: [(folder: VaporFolder, entry: VaporLedgerEntry)] = []
        var failed = 0
        for outcome in outcomes {
            switch outcome {
            case .staged(let id, let entry):
                guard let folder = targets.first(where: { $0.id == id }) else { continue }
                staged.append((folder, entry))
                measureTasks.removeValue(forKey: id)?.cancel()
            case .failed(let id, let failure):
                failed += 1
                if let index = folders.firstIndex(where: { $0.id == id }) { folders[index].failure = failure }
            }
        }
        let stagedIDs = Set(staged.map(\.folder.id))
        folders.removeAll { stagedIDs.contains($0.id) }
        persistFolders()
        guard !staged.isEmpty else {
            show(.failed(count: failed), for: Self.noticeDuration)
            return
        }
        let batch = PendingBatch(items: staged, failed: failed)
        pending = batch
        dependencies.analytics(.deleted(count: staged.count, bytes: batch.bytes))
        let deadline = dependencies.now().addingTimeInterval(Self.seconds(Self.undoWindow))
        status = VaporStatus(kind: .deleted(count: staged.count, failed: failed, deadline: deadline))
        let sleep = dependencies.sleep
        undoTask = Task { [weak self] in
            do { try await sleep(Self.undoWindow) } catch { return }
            guard !Task.isCancelled else { return }
            self?.commitPending(showFreed: true)
        }
    }

    /// Ends the undo window and removes the staged folders in the background.
    private func commitPending(showFreed: Bool) {
        undoTask?.cancel()
        undoTask = nil
        guard let batch = pending else { return }
        pending = nil
        if showFreed {
            show(.freed(bytes: batch.bytes, count: batch.items.count, failed: batch.failed), for: Self.freedDuration)
        }
        startRemoval(batch.entries)
    }

    private func startRemoval(_ entries: [VaporLedgerEntry]) {
        guard !entries.isEmpty else { return }
        let deleter = dependencies.deleter
        removalTasks.removeAll { $0.isCancelled }
        let task = Task(priority: .utility) { _ = await deleter.remove(entries) }
        removalTasks.append(task)
    }

    /// Renames the staged folders back, then shows "Put back …". Folders whose path is taken
    /// stay staged and are removed.
    /// - Returns: The restore task, for tests to await. Nil outside an undo window.
    @discardableResult
    func undo() -> Task<Void, Never>? {
        guard let batch = pending else { return nil }
        pending = nil
        undoTask?.cancel()
        undoTask = nil
        statusTask?.cancel()
        statusTask = nil
        // The capsule stays until the renames are done, then becomes "Put back …" in place.
        let deleter = dependencies.deleter
        return Task { [weak self] in
            let outcomes = await deleter.restore(batch.entries)
            self?.finishRestore(outcomes, batch: batch)
        }
    }

    private func finishRestore(_ outcomes: [VaporRestoreOutcome], batch: PendingBatch) {
        var restored: [VaporFolder] = []
        var leftover: [VaporLedgerEntry] = []
        for outcome in outcomes {
            switch outcome {
            case .restored(let entry):
                guard let folder = batch.items.first(where: { $0.entry.id == entry.id })?.folder else { continue }
                // A folder added meanwhile may now contain it; then it's back on disk but not re-added.
                guard !folders.contains(where: { folder.url.isSameOrDescendant(of: $0.url, resolvingSymlinks: false) }) else {
                    continue
                }
                folders.append(folder)
                restored.append(folder)
                if folder.measurement.isPending { measure(folder) }
            case .pathTaken(let entry), .failed(let entry, _):
                leftover.append(entry)
            }
        }
        if !restored.isEmpty {
            persistFolders()
            addition = VaporEvent(VaporAddition(folderIDs: restored.map(\.id), source: .restore))
        }
        dependencies.analytics(.undone(count: restored.count))
        if !leftover.isEmpty {
            startRemoval(leftover)
            show(.notRestored(count: leftover.count), for: Self.noticeDuration)
        } else if !restored.isEmpty {
            show(.restored(count: restored.count), for: Self.restoredDuration)
        } else {
            status = nil
        }
    }

    /// Shows a capsule for `duration`. One that follows "Deleted…" keeps that capsule's token,
    /// so the text changes in place instead of a new capsule popping in.
    private func show(_ kind: VaporStatus.Kind, for duration: Duration) {
        statusTask?.cancel()
        var status = VaporStatus(kind: kind)
        if undoDeadline != nil, let token = self.status?.token { status.token = token }
        self.status = status
        let sleep = dependencies.sleep
        statusTask = Task { [weak self] in
            do { try await sleep(duration) } catch { return }
            guard !Task.isCancelled, let self, self.status?.token == status.token else { return }
            self.status = nil
            self.statusTask = nil
        }
    }

    /// Hides the capsule now, for example when the person clicks it away.
    func dismissStatus() {
        guard let kind = status?.kind else { return }
        if case .deleted = kind { return }
        statusTask?.cancel()
        statusTask = nil
        status = nil
    }

    // MARK: Finder suggestions

    /// The Finder folder changed. A different folder clears an earlier dismissal.
    func setFinderFolder(_ folder: URL, items: [VaporSuggestion]) {
        if folder != dismissedFinderFolder { dismissedFinderFolder = nil }
        finderFolder = folder
        finderItems = items
        if let hoveredSuggestionID, !items.contains(where: { $0.id == hoveredSuggestionID }) {
            self.hoveredSuggestionID = nil
        }
    }

    /// Finder isn't frontmost, or its window shows no folder. The dismissal is kept.
    func clearFinderFolder() {
        finderFolder = nil
        finderItems = []
        hoveredSuggestionID = nil
    }

    /// × on the capsule: hides suggestions for this folder until Finder shows a different one.
    func dismissSuggestions() {
        dismissedFinderFolder = finderFolder
        hoveredSuggestionID = nil
    }

    func addSuggestion(_ suggestion: VaporSuggestion) {
        if hoveredSuggestionID == suggestion.id { hoveredSuggestionID = nil }
        add([suggestion.url], source: .suggestion)
    }

    func addAllSuggestions() {
        let urls = suggestions.map(\.url)
        guard !urls.isEmpty else { return }
        hoveredSuggestionID = nil
        add(urls, source: .addAll)
    }

    // MARK: Helpers

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

#if DEBUG
extension VaporController {
    /// Previews only: sets view-facing state directly, without measuring, staging or reading Finder.
    func loadPreviewState(folders: [VaporFolder], status: VaporStatus? = nil, isPanelOpen: Bool = false,
                          finderFolder: URL? = nil, finderItems: [VaporSuggestion] = [],
                          permission: VaporAutomationPermission = .granted, refusal: VaporRefusal? = nil,
                          hold: VaporHoldProgress = VaporHoldProgress()) {
        self.folders = folders
        self.hold = hold
        self.status = status
        self.isPanelOpen = isPanelOpen
        self.finderFolder = finderFolder
        self.finderItems = finderItems
        automationPermission = permission
        self.refusal = refusal.map(VaporEvent.init)
    }
}
#endif
