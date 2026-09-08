import AppKit
import Observation

/// Presentation-scoped metadata and ranking. Ending the Launcher cancels discovery and invalidates every result.
@MainActor @Observable
final class LauncherSearchState {
    var kind: LauncherSearchKind = .all { didSet { invalidateQuery() } }
    private(set) var results: [LauncherSearchResult] = []
    var selectedID: LauncherSearchID?
    private(set) var limit = 40
    private(set) var ranking = false
    private(set) var discovering = false
    private(set) var windowRevision = UUID()
    private(set) var message: LocalizedStringResource?
    var actionError: String?
    private(set) var actionBusy = false
    private(set) var active = false
    var shelf: ShelfController?
    var capsules: SessionCapsuleController?
    var actions: ActionTilesController?
    var modes: DockModesStore?
    @ObservationIgnored var dispatch: ((LauncherSearchResult, Bool) -> Void)?
    @ObservationIgnored var explicitSearch: (() -> Void)?
    @ObservationIgnored private var service: WindowSearchService?
    @ObservationIgnored private var sources: [WindowSearchSource] = []
    @ObservationIgnored private var discovery: Task<Void, Never>?
    @ObservationIgnored private var activation: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var queryGeneration = UUID()

    var visible: [LauncherSearchResult] { Array(results.prefix(limit)) }
    var incompleteStores: Bool {
        shelf?.requiresReset == true || capsules?.requiresReset == true
            || actions?.requiresReset == true || modes?.requiresReset == true
    }

    func input(query: String, applications: [LauncherApplication]) -> LauncherSearchInput {
        LauncherSearchInput(query: query, kind: kind, applications: applications,
            capsules: capsules?.capsules ?? [], shelf: shelf?.items ?? [], shortcuts: actions?.tiles ?? [],
            modes: modes?.modes.map { LauncherSearchName(id: $0.id, name: $0.name) } ?? [],
            windowRevision: windowRevision)
    }

    func begin() {
        active = true; selectedID = nil; actionError = nil; actionBusy = false
        refreshWindows()
    }

    /// Discovery happens on presentation or explicit refresh, never because a query changed.
    func refreshWindows() {
        guard active, !actionBusy else { return }
        discovery?.cancel(); activation?.cancel(); generation = UUID()
        actionBusy = false
        let previous = service
        let service = WindowSearchService()
        self.service = service
        sources = []; windowRevision = UUID(); invalidateQuery()
        discovering = true; message = nil
        let token = generation
        discovery = Task { [weak self] in
            await previous?.stop()
            do {
                let found = try await service.discover()
                guard !Task.isCancelled, let self, active, generation == token else { return }
                sources = found; windowRevision = UUID(); discovering = false
                message = found.contains(where: { $0.window != nil }) ? .unifiedMetadataSnapshot : .unifiedWindowUnavailable
            } catch {
                guard !Task.isCancelled, let self, active, generation == token else { return }
                discovering = false; message = .windowSearchUnavailable
            }
        }
    }

    func invalidateQuery() {
        queryGeneration = UUID(); results = []; limit = 40; ranking = true
        // Retain a selection tombstone until ranking confirms it, or the user moves again.
        // Return must never turn a disappearing selected object into a different first result.
    }

    /// SwiftUI owns this task and cancels it when any copied input changes or the view disappears.
    func rank(_ input: LauncherSearchInput) async {
        guard active else { ranking = false; return }
        let token = queryGeneration, session = generation
        ranking = true
        do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
        let next = await LauncherSearchIndex.results(input, windows: sources)
        guard !Task.isCancelled, active, queryGeneration == token, generation == session else { return }
        results = next; ranking = false
        if let selectedID, let index = next.firstIndex(where: { $0.id == selectedID }) {
            limit = max(limit, ((index / 40) + 1) * 40)
        }
    }

    func revealMore() { limit += 40 }

    func moveSelection(by offset: Int) {
        let values = visible
        guard !values.isEmpty else { return }
        let index = selectedID.flatMap { id in values.firstIndex { $0.id == id } }
        selectedID = values[index.map { min(max($0 + offset, 0), values.count - 1) } ?? 0].id
    }

    func openSelection() {
        guard !ranking else { return }
        if let selectedID {
            guard let result = visible.first(where: { $0.id == selectedID }) else { return }
            activate(result)
        } else if let first = visible.first {
            activate(first)
        }
    }

    func activate(_ result: LauncherSearchResult, reveal: Bool = false) {
        guard active, !actionBusy, !ranking, results.contains(where: { $0.id == result.id }), !result.unavailable else { return }
        actionError = nil
        dispatch?(result, reveal)
    }

    /// The coordinator calls this route so AX activation keeps the service that created its tokens.
    func activateWindow(_ source: WindowSearchSource, completion: @escaping () -> Void) {
        guard let service, !actionBusy, source.window != nil else { return }
        actionBusy = true
        let token = generation
        activation = Task { [weak self] in
            do {
                try await service.activate(source)
                guard !Task.isCancelled, let self, active, generation == token else { return }
                actionBusy = false; completion()
            } catch {
                guard !Task.isCancelled, let self, active, generation == token else { return }
                actionBusy = false; actionError = String(localized: .windowSearchStale)
            }
        }
    }

    /// Serializes a user action while its existing owner completes it. Old presentations cannot receive its feedback.
    func performOwnedAction(_ operation: (@escaping (String?) -> Void) -> Void, completion: @escaping () -> Void) {
        guard active, !actionBusy else { return }
        actionBusy = true
        let token = generation
        operation { [weak self] error in
            guard let self, active, generation == token else { return }
            actionBusy = false; actionError = error
            if error == nil { completion() }
        }
    }

    func stop() {
        active = false; generation = UUID(); queryGeneration = UUID()
        discovery?.cancel(); discovery = nil; activation?.cancel(); activation = nil
        sources = []; results = []; selectedID = nil; ranking = false; discovering = false; actionBusy = false
        let service = service; self.service = nil
        Task { await service?.stop() }
    }
}
