import AppKit
import Observation

/// Presentation-owned file-action mode: one batch, one chooser, one in-flight operation.
@MainActor @Observable
final class LauncherFileActionState {
    private(set) var context: LauncherFileContext?
    private(set) var overflowed = false
    private(set) var actions: [LauncherFileActionItem] = []
    var selectedID: LauncherFileActionID?
    var kind: LauncherFileActionKind = .all {
        didSet { if oldValue != kind { filter(query: lastQuery) } }
    }
    private(set) var status: LauncherFileOperationStatus = .idle
    private(set) var ranking = false
    private(set) var limit = 40
    var destinations = LauncherFileDestinationsStore()
    @ObservationIgnored var actionsController: ActionTilesController?
    @ObservationIgnored var catalog: ApplicationCatalog?
    @ObservationIgnored var didOpen: (() -> Void)?
    @ObservationIgnored private var lastQuery = ""
    @ObservationIgnored private var compatibility: LauncherFileCompatibility.Snapshot?
    @ObservationIgnored private var catalogItems: [LauncherFileActionItem] = []
    @ObservationIgnored private let chooser = LauncherFileChooser()
    @ObservationIgnored private var contextGeneration = UUID()
    @ObservationIgnored private var operationGeneration = UUID()
    @ObservationIgnored private var discovery: Task<Void, Never>?
    @ObservationIgnored private var operation: Task<Void, Never>?

    var isActive: Bool { context != nil }
    var isBusy: Bool { status.isPending || chooser.isChoosing }
    /// True while a native file or folder panel is open. Presentation monitors must not
    /// dismiss the launcher for that interval; collapsing it cancels the panel.
    var isChoosing: Bool { chooser.isChoosing }

    /// In-process file or folder panels this mode presented. Powerbox panels have no window here.
    func ownsChooserWindow(_ window: NSWindow) -> Bool { chooser.owns(window) }

    func configure(destinations: LauncherFileDestinationsStore, actions: ActionTilesController,
                   catalog: ApplicationCatalog) {
        self.destinations = destinations
        actionsController = actions
        self.catalog = catalog
    }

    func resetForPresentation() {
        cancelWork()
        context = nil
        overflowed = false
        actions = []
        catalogItems = []
        selectedID = nil
        kind = .all
        status = .idle
        ranking = false
        limit = 40
        compatibility = nil
        contextGeneration = UUID()
        operationGeneration = UUID()
    }

    func end() {
        chooser.cancel()
        resetForPresentation()
        didOpen = nil
    }

    /// Replaces the current batch. The supplied access object is kept; URLs are not re-leased.
    func adopt(_ adoption: LauncherFileAdoption) {
        cancelWork()
        let generation = UUID()
        contextGeneration = generation
        operationGeneration = UUID()
        status = .idle
        selectedID = nil
        limit = 40
        overflowed = adoption.overflowed
        context = LauncherFileContext(generation: generation, source: adoption.source,
                                      access: adoption.access, inputs: adoption.inputs)
        compatibility = nil
        rebuildCatalog()
        let urls = adoption.inputs.filter(\.isAvailable).map(\.url)
        guard !urls.isEmpty else { ranking = false; return }
        ranking = true
        discovery = Task { @concurrent in
            let snapshot = LauncherFileCompatibility.snapshot(urls: urls)
            await MainActor.run { [weak self] in
                guard let self, contextGeneration == generation else { return }
                compatibility = snapshot
                rebuildCatalog()
                ranking = false
            }
        }
    }

    func clear() {
        cancelWork()
        context = nil
        overflowed = false
        actions = []
        catalogItems = []
        selectedID = nil
        status = .idle
        ranking = false
        compatibility = nil
        contextGeneration = UUID()
    }

    /// Drops one input. An empty batch returns to ordinary search.
    func remove(_ id: UUID) {
        guard let context, !status.isPending else { return }
        let remaining = context.inputs.filter { $0.id != id }
        guard !remaining.isEmpty else { clear(); return }
        let remainingURLs = remaining.filter(\.isAvailable).map(\.url)
        let access = remainingURLs.isEmpty ? nil : DocumentResourceAccess(
            remainingURLs,
            retaining: context.access.map { [$0] } ?? [],
            startAccess: { _ in false },
            stopAccess: { _ in }
        )
        adopt(LauncherFileAdoption(source: context.source, access: access, inputs: remaining, overflowed: false))
    }

    func chooseFiles() {
        guard !status.isPending else { return }
        let token = contextGeneration
        chooser.chooseFiles { [weak self] urls in
            guard let self, contextGeneration == token else { return }
            guard let urls, !urls.isEmpty else { return }
            adopt(.owned(DocumentResourceAccess(urls), source: .picker))
        }
    }

    func refreshCatalog() { rebuildCatalog() }

    func filter(query: String) {
        lastQuery = query
        let kind = kind
        let items = LauncherFileActionCatalog.matching(catalogItems, query: query).filter { item in
            switch kind {
            case .all: return true
            case .application: if case .openWith = item.id { return true }; return false
            case .shortcut: if case .shortcut = item.id { return true }; return false
            case .folder:
                if case .copyTo = item.id { return true }
                if case .chooseFolder = item.id { return true }
                return false
            }
        }
        actions = items
        if let selectedID, let index = items.firstIndex(where: { $0.id == selectedID }) {
            limit = max(limit, ((index / 40) + 1) * 40)
        } else if selectedID != nil, !items.contains(where: { $0.id == selectedID }) {
            // A disappeared selection must not silently become the first remaining row.
        }
    }

    var visible: [LauncherFileActionItem] { Array(actions.prefix(limit)) }
    func revealMore() { limit += 40 }

    func moveSelection(by offset: Int) {
        let values = visible
        guard !values.isEmpty else { return }
        let index = selectedID.flatMap { id in values.firstIndex { $0.id == id } }
        guard let index else { selectedID = values.first?.id; return }
        selectedID = values[min(max(index + offset, 0), values.count - 1)].id
    }

    func openSelection() {
        if let selectedID {
            guard let item = visible.first(where: { $0.id == selectedID }) else { return }
            activate(item)
        } else if let first = visible.first {
            activate(first)
        }
    }

    /// One deliberate activation. Hover, keyboard highlight, and repeated clicks while pending do nothing.
    func activate(_ item: LauncherFileActionItem) {
        guard isActive, !status.isPending, !ranking, actions.contains(where: { $0.id == item.id }) else { return }
        guard !item.unavailable || item.support == .mixed else { return }
        status = .pending
        let token = UUID()
        operationGeneration = token
        switch item.id {
        case .openWith(let id):
            openWith(id, item: item, token: token)
        case .shortcut(let id):
            runShortcut(id, token: token)
        case .copyTo(let id):
            copy(to: id, token: token)
        case .chooseFolder:
            chooseFolder(token: token)
        }
    }

    func shortcutStatus(for id: UUID) -> ActionTileStatus {
        actionsController?.statuses[id] ?? .idle
    }

    func cancelOperation() {
        operationGeneration = UUID()
        operation?.cancel()
        operation = nil
        if status.isPending { status = .idle }
    }

    // MARK: - Private

    private func rebuildCatalog() {
        guard let context else { catalogItems = []; actions = []; return }
        catalogItems = LauncherFileActionCatalog.items(
            inputs: context.inputs,
            applications: catalog?.launcherLibrary.applications ?? [],
            shortcuts: actionsController?.tiles ?? [],
            destinations: destinations.destinations,
            destinationAvailable: { [destinations] in destinations.isAvailable($0) },
            compatibility: compatibility
        )
        filter(query: lastQuery)
    }

    private func openWith(_ id: String, item: LauncherFileActionItem, token: UUID) {
        guard let context, let application = item.application,
              let catalog, let access = context.access else {
            fail(String(localized: .launcherFileUnavailableInputs), token: token)
            return
        }
        let supported: DocumentResourceAccess
        if item.support == .mixed {
            let urls = LauncherFileCompatibility.support(
                for: application.reference, urls: context.availableURLs, in: compatibility ?? .init(handlers: [:])
            ).supported
            guard !urls.isEmpty else {
                fail(String(localized: .launcherFileOpenWithNone), token: token)
                return
            }
            supported = DocumentResourceAccess(urls, retaining: [access], startAccess: { _ in false }, stopAccess: { _ in })
        } else {
            supported = access
        }
        catalog.openDocuments(supported, with: application.reference) { [weak self] error in
            guard let self, operationGeneration == token, context.generation == contextGeneration else { return }
            if let error {
                if item.support == .mixed {
                    status = .partial(String(localized: error) + "\n" + mixedDetail(item))
                } else {
                    status = .failed(String(localized: error))
                }
            } else if item.support == .mixed {
                status = .partial(mixedDetail(item))
            } else {
                status = .completed
                didOpen?()
            }
        }
    }

    private func runShortcut(_ id: UUID, token: UUID) {
        guard let context, let access = context.access, let actionsController else {
            fail(String(localized: .unifiedShortcutUnavailable), token: token)
            return
        }
        guard actionsController.tiles.contains(where: { $0.id == id }) else {
            fail(String(localized: .unifiedShortcutUnavailable), token: token)
            return
        }
        let started = actionsController.run(id, files: access) { [weak self] in
            guard let self, operationGeneration == token, context.generation == contextGeneration else { return }
            switch actionsController.statuses[id] ?? .idle {
            case .succeeded: status = .completed
            case .failed(let message): status = .failed(message)
            default: status = .failed(String(localized: .unifiedShortcutUnavailable))
            }
        }
        if !started { fail(String(localized: .unifiedShortcutUnavailable), token: token) }
    }

    private func copy(to id: UUID, token: UUID) {
        guard let context, let access = context.access else {
            fail(String(localized: .launcherFileUnavailableInputs), token: token)
            return
        }
        guard let destinationAccess = destinations.resolve(id),
              let destination = destinations.destinations.first(where: { $0.id == id }) else {
            fail(String(localized: .launcherFileDestinationUnavailable), token: token)
            return
        }
        let destinationName = destination.name
        let generation = context.generation
        operation = Task { @concurrent in
            let outcome = LauncherFileCopy.perform(access, to: destinationAccess.url,
                                                   destinationAccess: destinationAccess)
            await MainActor.run { [weak self] in
                guard let self, operationGeneration == token, context.generation == generation else { return }
                applyCopy(outcome, destinationName: destinationName, token: token)
            }
        }
    }

    private func chooseFolder(token: UUID) {
        chooser.chooseFolder { [weak self] url in
            guard let self, operationGeneration == token else { return }
            guard let url else {
                if operationGeneration == token { status = .idle }
                return
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let destination = destinations.add(url), let access = context?.access,
                  let destinationAccess = destinations.resolve(destination.id) else {
                fail(String(localized: .launcherFileDestinationBookmarkFailed), token: token)
                return
            }
            rebuildCatalog()
            let destinationName = destination.name
            let generation = context?.generation
            operation = Task { @concurrent in
                let outcome = LauncherFileCopy.perform(access, to: destinationAccess.url,
                                                       destinationAccess: destinationAccess)
                await MainActor.run { [weak self] in
                    guard let self, operationGeneration == token, context?.generation == generation else { return }
                    applyCopy(outcome, destinationName: destinationName, token: token)
                }
            }
        }
    }

    private func applyCopy(_ outcome: LauncherFileCopy.Outcome, destinationName: String, token: UUID) {
        guard operationGeneration == token else { return }
        if outcome.copied == 0 {
            let detail = outcome.failed.map { "\($0.name): \($0.message)" }.joined(separator: "\n")
            status = .failed(detail.isEmpty ? String(localized: .launcherFileCopyFailed) : detail)
            return
        }
        var lines: [String] = [String(localized: .launcherFileCopied(outcome.copied, destinationName))]
        if !outcome.renamed.isEmpty {
            lines.append(String(localized: .launcherFileRenamedToAvoidOverwrite))
            lines.append(contentsOf: outcome.renamed.map { "\($0.from) → \($0.to)" })
        }
        if !outcome.failed.isEmpty {
            lines.append(contentsOf: outcome.failed.map { "\($0.name): \($0.message)" })
            status = .partial(lines.joined(separator: "\n"))
        } else {
            status = .completed
            if !outcome.renamed.isEmpty { status = .partial(lines.joined(separator: "\n")) }
        }
    }

    private func mixedDetail(_ item: LauncherFileActionItem) -> String {
        String(localized: .launcherFileSkippedUnsupported(item.unsupportedNames.formatted()))
    }

    private func fail(_ message: String, token: UUID) {
        guard operationGeneration == token else { return }
        status = .failed(message)
    }

    private func cancelWork() {
        contextGeneration = UUID()
        operationGeneration = UUID()
        discovery?.cancel()
        discovery = nil
        operation?.cancel()
        operation = nil
        chooser.cancel()
    }
}
