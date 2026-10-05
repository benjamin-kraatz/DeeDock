import AppKit
import Observation
import UniformTypeIdentifiers

/// Bookmark resolution, the directory check, and the directory watch for one stack open.
/// All three can block in the kernel, so this is built on `VolumeReads`.
nonisolated private struct FolderStackOpening: Sendable {
    let access: FolderResourceAccess
    let isDirectory: Bool
    let monitor: FolderDirectoryMonitor?
    let refreshedBookmark: Data?
}

@MainActor @Observable
final class FolderStackState {
    let folder: FolderReference
    private(set) var directory: URL
    private(set) var history: [URL] = []
    var preview: DockFilePreviewItem?
    var copying = false
    private(set) var receivedDrop = false
    var rootURL: URL { access?.url ?? folder.url }
    /// A native source must retain this lease even when another popover replaces its view.
    func dragLease() -> FolderResourceAccess? { access }
    var dropTargeted = false
    /// Volume stacks move dropped files while Shift is held; other stacks always copy.
    @ObservationIgnored var allowsMoveDrops = false
    /// What this stack shows, for analytics only.
    @ObservationIgnored var analyticsKind: AnalyticsStackKind = .folder
    /// Volume stacks turn the back button into a drop and spring-loading target, so a drag that
    /// sprang into a subfolder can climb out again. Other stacks keep a plain back button.
    var springsUp = false
    /// True while a file drag hovers the back button.
    var upTargeted = false
    /// True while the current drop target would move rather than copy, for the in-panel caption.
    var dropMoving = false
    /// True while a file drag is anywhere over this stack: its body, a folder row, or the back
    /// button. The back button widens to name its destination meanwhile.
    var dragInside = false
    /// The parent a back step returns to, or nil at the stack's root.
    var parentDirectory: URL? { history.last }
    var parentName: String? {
        guard let parent = history.last else { return nil }
        return history.count == 1 ? folder.name : parent.lastPathComponent
    }
    @ObservationIgnored var copyFailed: ((String) -> Void)?
    var directoryName: String { history.isEmpty ? folder.name : directory.lastPathComponent }
    private(set) var entries: [FolderStackEntry] = []
    private(set) var loading = false
    private(set) var semanticSections: [SemanticStackSection] = []
    private(set) var organizing = false
    private(set) var semanticError: String?
    var error: String?
    /// Set with `error` when macOS refused to list the folder, so the panel can offer a way around it.
    private(set) var accessDenial: FolderStackAccessDenial?
    /// Narrows what the panel shows without touching the loaded listing. Cleared on navigation.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            reconcileSelection()
        }
    }
    /// Mirrors the field's focus so the panel's key handler can leave text editing alone.
    var searchFocused = false
    private(set) var sort: FolderStackSort
    @ObservationIgnored var sortChanged: ((FolderStackSort) -> Void)?
    var presentation: FolderStackPresentation
    var selectedID: String?
    var presentationFocused = false
    var chrome = DockPopoverChrome(edge: .bottom, attachment: DockPopoverGeometry.idealSize.width / 2)
    @ObservationIgnored var stageOnShelf: ((FolderStackEntryReference) -> Void)?
    @ObservationIgnored var openEntry: ((FolderStackEntryReference) -> Void)?
    @ObservationIgnored var presentationChanged: ((FolderStackPresentation) -> Bool)?
    @ObservationIgnored var dragCompleted: ((Bool) -> Void)?
    @ObservationIgnored private var retryAction: (() -> Void)?
    @ObservationIgnored private var access: FolderResourceAccess?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var metricsTask: Task<Void, Never>?
    @ObservationIgnored private var mediaTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var openTask: Task<Bool, Never>?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var monitor: FolderDirectoryMonitor?
    /// Distinguishes a directory-watch install from a listing reload. `reload` changes `generation`.
    @ObservationIgnored private var monitorToken = UUID()
    @ObservationIgnored private var pendingDrop: PendingDrop?
    /// Persists a refreshed security-scoped bookmark. False aborts the open before the panel appears.
    @ObservationIgnored var bookmarkRefresh: ((Data) -> Bool)?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var semanticGeneration = UUID()
    @ObservationIgnored private var semanticTask: Task<Void, Never>?
    @ObservationIgnored private let organizer: any SemanticStackOrganizing
    @ObservationIgnored private let mediaCache: FolderStackMediaCache
    /// Per-file icon lookup. Tests pass a loader that suspends; production asks `NSWorkspace`.
    @ObservationIgnored private let resolveFileIcon: @MainActor (String) async -> NSImage

    init(folder: FolderReference, entries: [FolderStackEntry] = [], loading: Bool = false,
         error: String? = nil, accessDenial: FolderStackAccessDenial? = nil,
         sort: FolderStackSort = .alphabetical,
         organizer: any SemanticStackOrganizing = UnavailableSemanticStackOrganizer(),
         mediaCache: FolderStackMediaCache = .shared,
         resolveFileIcon: (@MainActor (String) async -> NSImage)? = nil) {
        self.sort = sort
        self.folder = folder
        directory = folder.url
        self.organizer = organizer
        self.mediaCache = mediaCache
        self.resolveFileIcon = resolveFileIcon ?? Self.workspaceIcon
        presentation = folder.presentation
        self.entries = entries.sorted { sort.precedes($0.reference, $1.reference) }
        self.loading = loading
        self.error = error
        self.accessDenial = accessDenial
        selectedID = self.entries.first?.id
        if presentation == .smart, !entries.isEmpty { refreshSemanticOrganization() }
    }

    func start() {
        openTask?.cancel()
        openTask = Task { [weak self] in await self?.openRoot() ?? false }
    }

    /// Waits for ``start()``. False when that open was cancelled or the refreshed bookmark could not be saved.
    func waitUntilOpen() async -> Bool {
        await openTask?.value ?? false
    }

    /// Resolves the bookmark, checks the directory, and creates the watch on `VolumeReads`.
    /// The panel stays hidden until this returns. A close during the read discards the watch.
    private func openRoot() async -> Bool {
        guard !Task.isCancelled else { return false }
        let token = UUID()
        generation = token
        loadTask?.cancel(); loadTask = nil
        metricsTask?.cancel(); metricsTask = nil
        mediaTask?.cancel(); mediaTask = nil
        previewTask?.cancel(); previewTask = nil
        monitorTask?.cancel(); monitorTask = nil
        monitorToken = UUID()
        monitor?.stop(); monitor = nil
        access = nil
        let folder = folder
        let changed = watchHandler()
        let opened = await VolumeReads.run { Self.opening(folder, changed: changed) }
        guard !Task.isCancelled, generation == token else {
            opened.monitor?.stop()
            return false
        }
        if let bookmark = opened.refreshedBookmark {
            let saved = bookmarkRefresh?(bookmark) ?? true
            guard !Task.isCancelled, generation == token else {
                opened.monitor?.stop()
                return false
            }
            guard saved else {
                opened.monitor?.stop()
                flushPendingDrop(available: false)
                return false
            }
        }
        access = opened.access
        guard opened.isDirectory else {
            loading = false
            flushPendingDrop(available: false)
            report(String(localized: .folderStackUnavailable)) { [weak self] in self?.start() }
            return true
        }
        directory = opened.access.url
        history = []
        monitor = opened.monitor
        reload()
        flushPendingDrop(available: true)
        return true
    }

    /// Runs on `VolumeReads`. Security scope starts there with the bookmark resolution.
    nonisolated private static func opening(_ folder: FolderReference,
                                            changed: @escaping @Sendable () -> Void) -> FolderStackOpening {
        let access = FolderResourceAccess(folder)
        guard access.isAvailable else {
            return FolderStackOpening(access: access, isDirectory: false, monitor: nil, refreshedBookmark: nil)
        }
        let refreshed = access.bookmarkIsStale ? try? access.url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil) : nil
        return FolderStackOpening(access: access, isDirectory: true,
                                  monitor: FolderDirectoryMonitor(url: access.url, changed: changed),
                                  refreshedBookmark: refreshed)
    }

    func reload() {
        guard let access else { return }
        loadTask?.cancel()
        metricsTask?.cancel()
        mediaTask?.cancel()
        semanticGeneration = UUID()
        semanticTask?.cancel()
        generation = UUID()
        let token = generation
        let directory = directory
        loading = true
        error = nil
        accessDenial = nil
        retryAction = nil
        loadTask = Task { [weak self] in
            let worker = Task.detached { Result { try FolderStackLoader.contents(of: access, directory: directory) } }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled, generation == token else { return }
            loading = false
            switch result {
            case .success(let references):
                let cacheHits = await FolderContentsMetricsCache.shared.hits(
                    for: references.filter(\.isFolder).map { ($0.url, $0.modifiedAt) }
                )
                guard !Task.isCancelled, generation == token else { return }
                entries = references.map { reference in
                    let contents = cacheHits[reference.id]
                    return FolderStackEntry(
                        reference: contents.map(reference.withContents) ?? reference,
                        icon: Self.placeholderIcon(for: reference)
                    )
                }
                entries.sort { self.sort.precedes($0.reference, $1.reference) }
                if self.selectedID == nil || !visibleEntries.contains(where: { $0.id == self.selectedID }) {
                    self.selectedID = visibleEntries.first?.id
                }
                if let preview, !entries.contains(where: { $0.reference.url == preview.url }) {
                    self.preview = nil
                }
                refreshSemanticOrganization()
                refreshContentsMetrics()
                enrichMedia(from: references, access: access, token: token)
                await fillIcons(token: token)
            case .failure(let error):
                report(error.localizedDescription) { [weak self] in self?.reload() }
                accessDenial = FolderStackAccessDenial(error)
            }
            // A reload already replaced `loadTask`. Clearing it here would drop that newer listing.
            guard !Task.isCancelled, generation == token else { return }
            loadTask = nil
        }
    }

    /// Point size requested from `NSWorkspace` so a filled icon matches the previous listing.
    private static let iconSize = NSSize(width: 128, height: 128)
    /// File-icon lookups between yields. Small enough that clicks, drags, and drawing can run.
    private static let iconBatchSize = 16
    /// One sized type icon per UTI. Copying leaves the workspace's shared image unchanged.
    private static var placeholderIcons: [String: NSImage] = [:]

    /// Default `icon(forFile:)` lookup. The loader type is async so tests can suspend; this call does not.
    private static func workspaceIcon(_ path: String) async -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = iconSize
        return icon
    }

    /// A folder or UTI icon. `icon(forFile:)` is the per-child lookup that stalls a large stack.
    private static func placeholderIcon(for reference: FolderStackEntryReference) -> NSImage {
        let key = reference.isFolder ? UTType.folder.identifier : (reference.contentType ?? UTType.item.identifier)
        if let cached = placeholderIcons[key] { return cached }
        let type = reference.isFolder ? UTType.folder : (reference.contentType.flatMap { UTType($0) } ?? .item)
        let icon = (NSWorkspace.shared.icon(for: type).copy() as? NSImage) ?? NSImage(size: iconSize)
        icon.size = iconSize
        placeholderIcons[key] = icon
        return icon
    }

    /// Fills file icons after the listing is already visible.
    ///
    /// The lookup stays on the main actor: `NSImage` is not `Sendable`, so doing it off-main would
    /// still hop back to publish. Each batch yields so the dock can draw and take clicks. `stop()`
    /// and `reload()` cancel this task and change `generation`; a stale batch returns without writing.
    private func fillIcons(token: UUID) async {
        guard !entries.isEmpty else { return }
        await Task.yield()
        guard !Task.isCancelled, generation == token else { return }
        let pending = entries.map { (id: $0.id, path: $0.reference.url.path) }
        var offset = 0
        while offset < pending.count {
            guard !Task.isCancelled, generation == token else { return }
            let end = min(offset + Self.iconBatchSize, pending.count)
            var icons: [String: NSImage] = [:]
            icons.reserveCapacity(end - offset)
            for item in pending[offset..<end] {
                guard !Task.isCancelled, generation == token else { return }
                icons[item.id] = await resolveFileIcon(item.path)
            }
            guard !Task.isCancelled, generation == token else { return }
            entries = entries.map { entry in
                guard let icon = icons[entry.id] else { return entry }
                return FolderStackEntry(reference: entry.reference, icon: icon)
            }
            offset = end
            if offset < pending.count { await Task.yield() }
        }
    }

    /// Keeps the root bookmark alive while browsing only real descendants, never aliases or packages.
    func navigate(to url: URL) {
        guard !QuarantineStore.shared.blocks(url) else { return }
        guard !copying, entries.contains(where: { $0.reference.url == url && $0.reference.isFolder }) else { return }
        history.append(directory)
        changeDirectory(url)
    }

    func back() {
        guard !copying, let previous = history.popLast() else { return }
        changeDirectory(previous)
    }

    private func changeDirectory(_ url: URL) {
        preview = nil
        directory = url
        entries = []
        selectedID = nil
        // A query belongs to the listing it was typed against, never to the folder opened next.
        query = ""
        searchFocused = false
        previewTask?.cancel()
        debounceTask?.cancel()
        cancelSemanticOrganization(clearError: true)
        installMonitor(for: url)
        reload()
    }

    func previewSelection() {
        if preview != nil { preview = nil; return }
        guard let entry = entries.first(where: { $0.id == selectedID }), let access else { return }
        Analytics.performing(.keyboard) { showPreview(entry.reference, access: access) }
    }

    func showPreview(_ entry: FolderStackEntryReference) {
        guard !QuarantineStore.shared.blocks(entry.url) else { return }
        guard let access else { return }
        selectedID = entry.id
        showPreview(entry, access: access)
    }

    private func showPreview(_ entry: FolderStackEntryReference, access: FolderResourceAccess) {
        let path = entry.url.path
        let token = generation
        let trigger = Analytics.trigger()
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            let exists = await VolumeReads.run { FileManager.default.fileExists(atPath: path) }
            guard let self, !Task.isCancelled, generation == token else { return }
            guard exists else {
                report(String(localized: .folderStackItemUnavailable(itemName: entry.name))) { [weak self] in self?.reload() }
                return
            }
            preview = DockFilePreviewItem(url: entry.url, leases: [access])
            Analytics.track(.stackQuickLook(fileType: AnalyticsFileType(url: entry.url), trigger: trigger))
        }
    }

    /// What a drop here does: copy, or move with Shift in a volume stack. Empty while busy.
    func dropOperation(_ info: NSDraggingInfo) -> NSDragOperation {
        guard !copying else { return [] }
        return FolderFileDrop.operation(info, allowsMove: allowsMoveDrops)
    }

    /// Keeps the cursor hint and the in-panel caption in step with the target under the pointer.
    /// Only volume stacks show the cursor hint; other stacks keep their original caption.
    func dropTargetChanged(_ info: NSDraggingInfo?, destination: String) {
        let operation = info.map(dropOperation) ?? []
        dropMoving = operation == .move
        dragInside = !operation.isEmpty
        guard allowsMoveDrops else { return }
        if operation.isEmpty { DockDropHintController.shared.hide() }
        else { DockDropHintController.shared.show(destination: destination, moving: dropMoving, offersMove: true) }
    }

    /// Copies, or moves in a volume stack with Shift, into the current directory, an immediate
    /// folder child, or a folder on the way back up. Copying never alters the source.
    func receive(_ info: NSDraggingInfo, into url: URL? = nil, target: AnalyticsDropTarget = .stack) -> Bool {
        let operation = dropOperation(info)
        dropTargetChanged(nil, destination: "")
        guard !operation.isEmpty, let urls = FolderFileDrop.urls(info) else { return false }
        let destination = url ?? directory
        guard destination == rootURL || destination == directory || history.contains(destination) || entries.contains(where: {
            $0.reference.url == destination && $0.reference.isFolder
        }) else { return false }
        guard let access else {
            // A tile drop arrives in the same turn as `start`, before the volume read returns.
            guard openTask != nil else { return false }
            pendingDrop = PendingDrop(urls: urls, destination: destination, move: operation == .move, target: target)
            receivedDrop = true
            return true
        }
        beginCopy(urls, to: destination, move: operation == .move, target: target, access: access)
        return true
    }

    private struct PendingDrop {
        let urls: [URL]
        let destination: URL
        let move: Bool
        let target: AnalyticsDropTarget
    }

    /// A drop queued before the folder was resolved copies into the resolved root, not the stale path.
    private func flushPendingDrop(available: Bool) {
        guard let pending = pendingDrop else { return }
        pendingDrop = nil
        guard available, let access else {
            copyFailed?(String(localized: .folderStackUnavailable))
            return
        }
        let destination = pending.destination.standardizedFileURL == folder.url.standardizedFileURL
            ? access.url : pending.destination
        beginCopy(pending.urls, to: destination, move: pending.move, target: pending.target, access: access)
    }

    private func beginCopy(_ urls: [URL], to destination: URL, move: Bool, target: AnalyticsDropTarget,
                           access: FolderResourceAccess) {
        receivedDrop = true
        copying = true
        let failure = copyFailed
        let fileType = AnalyticsFileType.common(of: urls)
        FolderFileDrop.copy(urls, to: destination, lease: access, move: move) { [weak self] error in
            Analytics.track(.stackDrop(move ? .move : .copy, itemCount: urls.count, fileType: fileType,
                                       target: target, outcome: error == nil ? .succeeded : .failed))
            self?.copying = false
            self?.reload()
            if let error {
                failure?(error)
                self?.report(error) { [weak self] in self?.reload() }
            }
        }
    }

    /// Reorders loaded metadata without reloading icons or losing the selected file.
    func chooseSort(_ value: FolderStackSort) {
        guard value != sort else { return }
        sort = value
        entries.sort { value.precedes($0.reference, $1.reference) }
        sortChanged?(value)
        Analytics.track(.stackSorted(value, itemCount: entries.count))
    }

    /// The field earns its space only on long listings, and stays while a query is still narrowing one.
    var searchAvailable: Bool { entries.count > FolderStackSearchFilter.threshold || !query.isEmpty }

    /// True while a query actually filters. A whitespace-only query does not.
    var searching: Bool { !FolderStackSearchFilter.terms(in: query).isEmpty }

    /// The listing after the query, in the current sort order. Grid, list, and smart mode all draw from it.
    var visibleEntries: [FolderStackEntry] {
        let terms = FolderStackSearchFilter.terms(in: query)
        guard !terms.isEmpty else { return entries }
        return entries.filter { FolderStackSearchFilter.matches($0.reference, terms: terms) }
    }

    /// Moves keyboard focus into the field, or back out to the listing.
    func focusSearch(_ focused: Bool = true) {
        guard !focused || searchAvailable else { return }
        searchFocused = focused
    }

    func clearSearch() { query = "" }

    /// Finder-style type-ahead: the first character typed over the listing starts a search.
    func beginTypeAhead(_ characters: String) {
        guard searchAvailable else { return }
        query.append(characters)
        searchFocused = true
    }

    /// Keeps the selection on something the user can still see after the query changed.
    private func reconcileSelection() {
        let visible = displayedEntries
        guard !visible.contains(where: { $0.id == selectedID }) else { return }
        selectedID = visible.first?.id
        preview = nil
    }

    /// Smart mode keeps its groups and applies the selected order within each group.
    /// A query narrows every group and hides the ones it empties.
    var sortedSemanticSections: [SemanticStackSection] {
        let ranks = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.id, $0.offset) })
        let searching = searching
        let visible = searching ? Set(visibleEntries.map(\.id)) : []
        return semanticSections.compactMap { section in
            let itemIDs = (searching ? section.itemIDs.filter(visible.contains) : section.itemIDs)
                .sorted { (ranks[$0] ?? Int.max) < (ranks[$1] ?? Int.max) }
            guard !searching || !itemIDs.isEmpty else { return nil }
            return SemanticStackSection(id: section.id, title: section.title, itemIDs: itemIDs, kind: section.kind)
        }
    }

    func choose(_ value: FolderStackPresentation) {
        guard value != presentation else { return }
        let previous = presentation
        presentation = value
        if presentationChanged?(value) == true {
            Analytics.track(.stackPresentationChanged(value, kind: analyticsKind, trigger: Analytics.trigger()))
        } else {
            presentation = previous
            report(String(localized: .folderStackSaveFailed)) { [weak self] in self?.choose(value) }
            return
        }
        if value == .smart { refreshSemanticOrganization() }
        else { cancelSemanticOrganization(clearError: true) }
    }

    func report(_ message: String, retry: @escaping () -> Void) {
        error = message
        retryAction = retry
    }

    func retry() {
        let action = retryAction
        error = nil
        accessDenial = nil
        retryAction = nil
        action?()
    }

    func retrySemanticOrganization() {
        semanticError = nil
        refreshSemanticOrganization()
    }

    var displayedEntries: [FolderStackEntry] {
        guard presentation == .smart else { return visibleEntries }
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        return sortedSemanticSections.flatMap(\.itemIDs).compactMap { byID[$0] }
    }

    func select(by distance: Int) {
        let navigable = displayedEntries
        guard !navigable.isEmpty else { return }
        let current = selectedID.flatMap { id in navigable.firstIndex { $0.id == id } } ?? 0
        let index = ((current + distance) % navigable.count + navigable.count) % navigable.count
        selectedID = navigable[index].id
        if preview != nil { preview = nil; previewSelection() }
    }

    func openSelection() {
        guard let entry = entries.first(where: { $0.id == selectedID }) else { return }
        Analytics.performing(.keyboard) { openEntry?(entry.reference) }
    }

    /// Measures folder children after the listing is on screen. Navigation and dismissal cancel the walks.
    private func refreshContentsMetrics() {
        metricsTask?.cancel()
        let pending = entries.compactMap { entry -> FolderStackEntryReference? in
            guard entry.reference.isFolder, entry.reference.contents?.isFinal != true else { return nil }
            return entry.reference
        }
        guard !pending.isEmpty, let access else { return }
        let token = generation
        metricsTask = Task { [weak self] in
            let worker = Task.detached(priority: .utility) {
                await FolderContentsMetricsScheduler.measure(pending) { url, metrics in
                    await MainActor.run {
                        self?.applyMetrics(metrics, to: url, token: token)
                    }
                }
                withExtendedLifetime(access) {}
            }
            await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        }
    }

    /// Replaces one folder's contents metrics. Size sort waits for a finished total so rows do not jump mid-walk.
    private func applyMetrics(_ metrics: FolderContentsMetrics, to url: URL, token: UUID) {
        guard generation == token else { return }
        guard let index = entries.firstIndex(where: { $0.reference.url == url }) else { return }
        guard entries[index].reference.contents != metrics else { return }
        let selected = selectedID
        entries[index] = entries[index].withContents(metrics)
        if sort == .size, metrics.isFinal {
            entries.sort { sort.precedes($0.reference, $1.reference) }
        }
        selectedID = selected
    }

    /// Applies cached headers immediately, then reads the rest off the main actor while `access` stays alive.
    private func enrichMedia(from references: [FolderStackEntryReference],
                             access: FolderResourceAccess, token: UUID) {
        let candidates = references.filter(FolderStackMediaReader.isCandidate)
        guard !candidates.isEmpty else { return }
        let cache = mediaCache
        mediaTask = Task { [weak self] in
            var cachedHits: [String: FolderStackMediaMetadata] = [:]
            var pending: [FolderStackEntryReference] = []
            for reference in candidates {
                guard !Task.isCancelled else { return }
                if let cached = await cache.value(for: FolderStackMediaCacheKey(reference)) {
                    if case .metadata(let media) = cached { cachedHits[reference.id] = media }
                } else {
                    pending.append(reference)
                }
            }
            guard let self, !Task.isCancelled, generation == token else { return }
            applyMedia(cachedHits)
            guard !pending.isEmpty else {
                mediaTask = nil
                return
            }
            let worker = Task.detached {
                await FolderStackMediaReader.load(pending, cache: cache, access: access)
            }
            let loaded = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, generation == token else { return }
            applyMedia(loaded)
            mediaTask = nil
        }
    }

    private func applyMedia(_ media: [String: FolderStackMediaMetadata]) {
        guard !media.isEmpty else { return }
        entries = entries.map { entry in
            guard let value = media[entry.id], entry.reference.media != value else { return entry }
            return FolderStackEntry(reference: entry.reference.updating(media: value), icon: entry.icon)
        }
    }

    private func scheduleReload() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            self?.reload()
        }
    }

    private func watchHandler() -> @Sendable () -> Void {
        { [weak self] in
            Task { @MainActor [weak self] in self?.scheduleReload() }
        }
    }

    /// `open` on the watched path can stall, so the descriptor is created on `VolumeReads`.
    private func installMonitor(for url: URL) {
        monitor?.stop()
        monitor = nil
        monitorToken = UUID()
        let token = monitorToken
        let changed = watchHandler()
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            let installed = await VolumeReads.run { FolderDirectoryMonitor(url: url, changed: changed) }
            guard let self, !Task.isCancelled, monitorToken == token else {
                installed?.stop()
                return
            }
            monitor?.stop()
            monitor = installed
        }
    }

    private func refreshSemanticOrganization() {
        guard presentation == .smart else { return }
        semanticTask?.cancel()
        semanticGeneration = UUID()
        let token = semanticGeneration
        semanticError = nil

        let ranked = entries.sorted { lhs, rhs in
            let left = lhs.reference.modifiedAt ?? .distantPast
            let right = rhs.reference.modifiedAt ?? .distantPast
            if left != right { return left > right }
            let comparison = lhs.reference.name.localizedStandardCompare(rhs.reference.name)
            return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
        }
        let eligible = Array(ranked.prefix(60))
        let overflow = Array(ranked.dropFirst(60)).sorted {
            let comparison = $0.reference.name.localizedStandardCompare($1.reference.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
        let candidates = eligible.map(\.reference.semanticCandidate)
        let moreSection = overflow.isEmpty ? nil : SemanticStackSection(
            id: "more-items",
            title: String(localized: .semanticStackMoreItems),
            itemIDs: overflow.map(\.id),
            kind: .moreItems
        )

        guard candidates.count >= 4 else {
            var sections = SemanticStackNormalizer.fallback(
                candidates: candidates,
                title: String(localized: .semanticStackItems)
            ).sections
            if let moreSection { sections.append(moreSection) }
            semanticSections = sections
            organizing = false
            return
        }

        semanticSections = [SemanticStackSection(
            id: "organizing",
            title: String(localized: .semanticStackOrganizing),
            itemIDs: candidates.map(\.id),
            kind: .organizing
        )] + (moreSection.map { [$0] } ?? [])
        organizing = true
        let locale = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        let request = SemanticStackRequest(source: .folder(folder.id), candidates: candidates,
                                           localeIdentifier: locale)
        semanticTask = Task { [weak self] in
            guard let self else { return }
            let availability = await organizer.availability()
            guard !Task.isCancelled, semanticGeneration == token else { return }
            guard availability == .available else {
                applySemanticFailure(Self.message(for: availability), candidates: candidates,
                                     moreSection: moreSection, token: token)
                return
            }

            let stream = await organizer.snapshots(for: request)
            do {
                for try await snapshot in stream {
                    guard !Task.isCancelled, semanticGeneration == token else { return }
                    semanticSections = snapshot.sections + (moreSection.map { [$0] } ?? [])
                    organizing = !snapshot.isFinal
                    if snapshot.isFinal { announce(String(localized: .semanticStackFinished)) }
                }
            } catch is CancellationError {
                return
            } catch {
                guard semanticGeneration == token else { return }
                applySemanticFailure(String(localized: .semanticStackFailed), candidates: candidates,
                                     moreSection: moreSection, token: token)
            }
        }
    }

    private func applySemanticFailure(_ message: String, candidates: [SemanticStackCandidate],
                                      moreSection: SemanticStackSection?, token: UUID) {
        guard semanticGeneration == token else { return }
        semanticError = message
        organizing = false
        semanticSections = SemanticStackNormalizer.fallback(
            candidates: candidates,
            title: String(localized: .semanticStackItems)
        ).sections + (moreSection.map { [$0] } ?? [])
        announce(message)
    }

    private func cancelSemanticOrganization(clearError: Bool) {
        semanticGeneration = UUID()
        semanticTask?.cancel()
        semanticTask = nil
        organizing = false
        semanticSections = []
        if clearError { semanticError = nil }
    }

    private static func message(for availability: SemanticStackAvailability) -> String {
        switch availability {
        case .available: String(localized: .semanticStackFailed)
        case .deviceNotEligible: String(localized: .semanticStackDeviceNotEligible)
        case .appleIntelligenceNotEnabled: String(localized: .semanticStackAppleIntelligenceDisabled)
        case .modelNotReady: String(localized: .semanticStackModelNotReady)
        }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }

    func stop() {
        generation = UUID()
        monitorToken = UUID()
        openTask?.cancel(); openTask = nil
        loadTask?.cancel(); loadTask = nil
        metricsTask?.cancel(); metricsTask = nil
        mediaTask?.cancel(); mediaTask = nil
        previewTask?.cancel(); previewTask = nil
        debounceTask?.cancel(); debounceTask = nil
        monitorTask?.cancel(); monitorTask = nil
        monitor?.stop(); monitor = nil
        pendingDrop = nil
        cancelSemanticOrganization(clearError: true)
        access = nil
        retryAction = nil
        preview = nil
        copyFailed = nil
        bookmarkRefresh = nil
        sortChanged = nil
        openEntry = nil; stageOnShelf = nil; presentationChanged = nil; dragCompleted = nil
    }
}
