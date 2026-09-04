import AppKit
import Observation

@MainActor @Observable
final class FolderStackState {
    let folder: FolderReference
    private(set) var entries: [FolderStackEntry] = []
    private(set) var loading = false
    private(set) var semanticSections: [SemanticStackSection] = []
    private(set) var organizing = false
    private(set) var semanticError: String?
    var error: String?
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
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var monitor: FolderDirectoryMonitor?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var semanticGeneration = UUID()
    @ObservationIgnored private var semanticTask: Task<Void, Never>?
    @ObservationIgnored private let organizer: any SemanticStackOrganizing

    init(folder: FolderReference, entries: [FolderStackEntry] = [], loading: Bool = false,
         error: String? = nil,
         organizer: any SemanticStackOrganizing = UnavailableSemanticStackOrganizer()) {
        self.folder = folder
        self.organizer = organizer
        presentation = folder.presentation
        self.entries = entries
        self.loading = loading
        self.error = error
        selectedID = entries.first?.id
        if presentation == .smart, !entries.isEmpty { refreshSemanticOrganization() }
    }

    func start() {
        loadTask?.cancel(); loadTask = nil
        monitor?.stop(); monitor = nil
        access = nil
        let access = FolderResourceAccess(folder)
        self.access = access
        guard access.isAvailable else {
            report(String(localized: .folderStackUnavailable)) { [weak self] in self?.start() }
            return
        }
        installMonitor(for: access.url)
        reload()
    }

    func reload() {
        guard let access else { return }
        loadTask?.cancel()
        semanticGeneration = UUID()
        semanticTask?.cancel()
        let token = generation
        loading = true
        error = nil
        retryAction = nil
        loadTask = Task { [weak self] in
            let worker = Task.detached { Result { try FolderStackLoader.contents(of: access) } }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled, generation == token else { return }
            loading = false
            switch result {
            case .success(let references):
                entries = references.map { reference in
                    let icon = NSWorkspace.shared.icon(forFile: reference.url.path)
                    icon.size = NSSize(width: 128, height: 128)
                    return FolderStackEntry(reference: reference, icon: icon)
                }
                if self.selectedID == nil || !entries.contains(where: { $0.id == self.selectedID }) {
                    self.selectedID = entries.first?.id
                }
                refreshSemanticOrganization()
            case .failure(let error):
                report(error.localizedDescription) { [weak self] in self?.reload() }
            }
            loadTask = nil
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
        return semanticSections.flatMap(\.itemIDs).compactMap { byID[$0] }
    }

    func select(by distance: Int) {
        let navigable = displayedEntries
        guard !navigable.isEmpty else { return }
        let current = selectedID.flatMap { id in navigable.firstIndex { $0.id == id } } ?? 0
        selectedID = navigable[(current + distance + navigable.count) % navigable.count].id
    }

    func openSelection() {
        guard let entry = entries.first(where: { $0.id == selectedID }) else { return }
        openEntry?(entry.reference)
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
        debounceTask?.cancel(); debounceTask = nil
        monitor?.stop(); monitor = nil
        cancelSemanticOrganization(clearError: true)
        access = nil
        retryAction = nil
        openEntry = nil; presentationChanged = nil; dragCompleted = nil
    }
}
