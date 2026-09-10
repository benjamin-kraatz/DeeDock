import AppKit
import Observation

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
    @ObservationIgnored var copyFailed: ((String) -> Void)?
    var directoryName: String { history.isEmpty ? folder.name : directory.lastPathComponent }
    private(set) var entries: [FolderStackEntry] = []
    private(set) var loading = false
    private(set) var semanticSections: [SemanticStackSection] = []
    private(set) var organizing = false
    private(set) var semanticError: String?
    var error: String?
    private(set) var sort: FolderStackSort
    @ObservationIgnored var sortChanged: ((FolderStackSort) -> Void)?
    var presentation: FolderStackPresentation
    var selectedID: String?
    var presentationFocused = false
    var chrome = DockPopoverChrome(edge: .bottom, attachment: DockPopoverGeometry.idealSize.width / 2)
    @ObservationIgnored var openEntry: ((FolderStackEntryReference) -> Void)?
    @ObservationIgnored var presentationChanged: ((FolderStackPresentation) -> Bool)?
    @ObservationIgnored var dragCompleted: ((Bool) -> Void)?
    @ObservationIgnored private var retryAction: (() -> Void)?
    @ObservationIgnored private var access: FolderResourceAccess?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var metricsTask: Task<Void, Never>?
    @ObservationIgnored private var mediaTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var monitor: FolderDirectoryMonitor?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var semanticGeneration = UUID()
    @ObservationIgnored private var semanticTask: Task<Void, Never>?
    @ObservationIgnored private let organizer: any SemanticStackOrganizing
    @ObservationIgnored private let mediaCache: FolderStackMediaCache

    init(folder: FolderReference, entries: [FolderStackEntry] = [], loading: Bool = false,
         error: String? = nil, sort: FolderStackSort = .alphabetical,
         organizer: any SemanticStackOrganizing = UnavailableSemanticStackOrganizer(),
         mediaCache: FolderStackMediaCache = .shared) {
        self.sort = sort
        self.folder = folder
        directory = folder.url
        self.organizer = organizer
        self.mediaCache = mediaCache
        presentation = folder.presentation
        self.entries = entries.sorted { sort.precedes($0.reference, $1.reference) }
        self.loading = loading
        self.error = error
        selectedID = self.entries.first?.id
        if presentation == .smart, !entries.isEmpty { refreshSemanticOrganization() }
    }

    func start() {
        loadTask?.cancel(); loadTask = nil
        metricsTask?.cancel(); metricsTask = nil
        mediaTask?.cancel(); mediaTask = nil
        monitor?.stop(); monitor = nil
        access = nil
        let access = FolderResourceAccess(folder)
        self.access = access
        guard access.isAvailable else {
            report(String(localized: .folderStackUnavailable)) { [weak self] in self?.start() }
            return
        }
        directory = access.url
        history = []
        installMonitor(for: directory)
        reload()
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
                    let icon = NSWorkspace.shared.icon(forFile: reference.url.path)
                    icon.size = NSSize(width: 128, height: 128)
                    let contents = cacheHits[reference.id]
                    return FolderStackEntry(
                        reference: contents.map(reference.withContents) ?? reference,
                        icon: icon
                    )
                }
                entries.sort { self.sort.precedes($0.reference, $1.reference) }
                if self.selectedID == nil || !entries.contains(where: { $0.id == self.selectedID }) {
                    self.selectedID = entries.first?.id
                }
                if let preview, !entries.contains(where: { $0.reference.url == preview.url }) {
                    self.preview = nil
                }
                refreshSemanticOrganization()
                refreshContentsMetrics()
                enrichMedia(from: references, access: access, token: token)
            case .failure(let error):
                report(error.localizedDescription) { [weak self] in self?.reload() }
            }
            loadTask = nil
        }
    }

    /// Keeps the root bookmark alive while browsing only real descendants, never aliases or packages.
    func navigate(to url: URL) {
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
        debounceTask?.cancel()
        cancelSemanticOrganization(clearError: true)
        installMonitor(for: url)
        reload()
    }

    func previewSelection() {
        if preview != nil { preview = nil; return }
        guard let entry = entries.first(where: { $0.id == selectedID }), let access else { return }
        showPreview(entry.reference, access: access)
    }

    func showPreview(_ entry: FolderStackEntryReference) {
        guard let access else { return }
        selectedID = entry.id
        showPreview(entry, access: access)
    }

    private func showPreview(_ entry: FolderStackEntryReference, access: FolderResourceAccess) {
        guard FileManager.default.fileExists(atPath: entry.url.path) else {
            report(String(localized: .folderStackItemUnavailable(itemName: entry.name))) { [weak self] in self?.reload() }
            return
        }
        preview = DockFilePreviewItem(url: entry.url, leases: [access])
    }

    /// Copies into the current directory or an immediate folder child; never alters the source.
    func receive(_ info: NSDraggingInfo, into url: URL? = nil) -> Bool {
        guard !copying, let urls = FolderFileDrop.urls(info), let access else { return false }
        let destination = url ?? directory
        guard destination == rootURL || destination == directory || entries.contains(where: {
            $0.reference.url == destination && $0.reference.isFolder
        }) else { return false }
        receivedDrop = true
        copying = true
        let failure = copyFailed
        FolderFileDrop.copy(urls, to: destination, lease: access) { [weak self] error in
            self?.copying = false
            self?.reload()
            if let error {
                failure?(error)
                self?.report(error) { [weak self] in self?.reload() }
            }
        }
        return true
    }

    /// Reorders loaded metadata without reloading icons or losing the selected file.
    func chooseSort(_ value: FolderStackSort) {
        guard value != sort else { return }
        sort = value
        entries.sort { value.precedes($0.reference, $1.reference) }
        sortChanged?(value)
    }

    /// Smart mode keeps its groups and applies the selected order within each group.
    var sortedSemanticSections: [SemanticStackSection] {
        let ranks = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.id, $0.offset) })
        return semanticSections.map { section in
            SemanticStackSection(id: section.id, title: section.title,
                itemIDs: section.itemIDs.sorted { (ranks[$0] ?? Int.max) < (ranks[$1] ?? Int.max) }, kind: section.kind)
        }
    }

    func choose(_ value: FolderStackPresentation) {
        guard value != presentation else { return }
        let previous = presentation
        presentation = value
        if presentationChanged?(value) != true {
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
        retryAction = nil
        action?()
    }

    func retrySemanticOrganization() {
        semanticError = nil
        refreshSemanticOrganization()
    }

    var displayedEntries: [FolderStackEntry] {
        guard presentation == .smart else { return entries }
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
        openEntry?(entry.reference)
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

    private func installMonitor(for url: URL) {
        monitor?.stop()
        monitor = FolderDirectoryMonitor(url: url) { [weak self] in
            Task { @MainActor [weak self] in self?.scheduleReload() }
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
        loadTask?.cancel(); loadTask = nil
        metricsTask?.cancel(); metricsTask = nil
        mediaTask?.cancel(); mediaTask = nil
        debounceTask?.cancel(); debounceTask = nil
        monitor?.stop(); monitor = nil
        cancelSemanticOrganization(clearError: true)
        access = nil
        retryAction = nil
        preview = nil
        copyFailed = nil
        sortChanged = nil
        openEntry = nil; presentationChanged = nil; dragCompleted = nil
    }
}
