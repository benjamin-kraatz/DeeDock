import AppKit
import Observation

/// Owns one search presentation. Closing or clearing invalidates work before releasing captured content.
@MainActor @Observable
final class WindowSearchState {
    var query = "" { didSet {
        if query.count > WindowSearchMatcher.maximumQuery { query = String(query.prefix(WindowSearchMatcher.maximumQuery)) }
        invalidateImageSearch(); results = []; selectedID = nil; rank()
    } }
    var scope = WindowSearchScope.live { didSet { invalidateImageSearch(); results = []; selectedID = nil; rank() } }
    var selectedID: UUID?
    var captureSelection: Set<CGWindowID> = []
    private(set) var sources: [WindowSearchSource] = []
    private(set) var candidates: [WindowContextCandidate] = []
    private(set) var snapshots: [WindowContextSnapshot] = []
    private(set) var capturedAt: Date?
    private(set) var results: [WindowSearchResult] = []
    private(set) var busy = false
    private(set) var choosingCapture = false
    var message: LocalizedStringResource?
    var openedCapsule: SessionCapsule?
    let capsules: SessionCapsuleController
    @ObservationIgnored var close: (() -> Void)?
    @ObservationIgnored var activated: (() -> Void)?
    @ObservationIgnored private let service = WindowSearchService()
    @ObservationIgnored private let capture: any WindowContextCapturing = ScreenCaptureWindowContextService()
    @ObservationIgnored private let imageMatcher = WindowSearchImageMatcher()
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var ranking: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var expiration: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var imageSearching = false
    @ObservationIgnored private var imageResults: [WindowSearchResult] = []
    @ObservationIgnored private var capturedSources: [CGWindowID: WindowSearchSource] = [:]
    @ObservationIgnored private var stopped = false

    init(capsules: SessionCapsuleController) { self.capsules = capsules }

    func refresh() {
        cancelWork(); busy = true; message = nil
        sources = []; results = []; selectedID = nil
        let generation = self.generation
        setDeadline()
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let found = try await service.discover()
                guard accepts(generation) else { return }
                sources = found; busy = false
                message = .windowSearchMetadataHelp
                rank()
            } catch {
                guard accepts(generation) else { return }
                busy = false; message = .windowSearchUnavailable
            }
        }
    }

    /// Opens a metadata-only picker. No screenshots exist until Capture Selected is pressed.
    func chooseCapture() {
        cancelWork(); busy = true; message = nil
        let generation = self.generation
        setDeadline()
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let found = try await capture.discover()
                guard accepts(generation) else { return }
                candidates = Array(found.prefix(WindowSearchMatcher.maximumSources))
                captureSelection = []; choosingCapture = true; busy = false
            } catch {
                guard accepts(generation) else { return }
                busy = false; message = .windowSearchCaptureUnavailable
            }
        }
    }

    func toggleCapture(_ candidate: WindowContextCandidate) {
        if captureSelection.contains(candidate.id) { captureSelection.remove(candidate.id) }
        else if captureSelection.count < WindowSearchMatcher.maximumCaptures { captureSelection.insert(candidate.id) }
    }

    func captureSelected() {
        let selected = Array(candidates.filter { captureSelection.contains($0.id) }.prefix(WindowSearchMatcher.maximumCaptures))
        guard !selected.isEmpty else { return }
        clearCaptured(); busy = true; choosingCapture = false; message = nil
        // Record process lifetimes before capture, so PID reuse cannot redirect activation later.
        let owners = Dictionary(uniqueKeysWithValues: selected.map { candidate in
            (candidate.id, WindowSearchSource(id: UUID(), applicationName: candidate.applicationName,
                processIdentifier: candidate.processIdentifier,
                launchDate: NSRunningApplication(processIdentifier: candidate.processIdentifier)?.launchDate,
                window: nil, candidate: candidate))
        })
        let generation = self.generation
        setDeadline()
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let found = try await capture.capture(selected)
                guard accepts(generation) else { return }
                snapshots = found.map { WindowContextSnapshot(candidate: $0.candidate, image: $0.image,
                    recognizedText: String($0.recognizedText.prefix(WindowSearchMatcher.maximumText))) }
                capturedSources = owners; capturedAt = Date(); busy = false
                scope = .captured; message = .windowSearchRetention
                expiration = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(600)) } catch { return }
                    self?.clearCaptured()
                    self?.message = .windowSearchExpired
                }
                rank()
            } catch {
                guard accepts(generation) else { return }
                busy = false; message = .windowSearchCaptureUnavailable
            }
        }
    }

    func searchImages() {
        guard !snapshots.isEmpty, !WindowSearchMatcher.terms(query).isEmpty,
              !WindowSearchMatcher.wantsYesterday(query) else { return }
        cancelWork(); imageResults = []; busy = true; imageSearching = true; message = nil
        let generation = self.generation
        let query = self.query
        let snapshots = self.snapshots
        setDeadline()
        work = Task { [weak self] in
            guard let self else { return }
            var matches: [WindowSearchResult] = []
            var unavailable = false
            for snapshot in snapshots where snapshot.image != nil {
                do {
                    if let evidence = try await imageMatcher.match(query: query, snapshot: snapshot),
                       let source = capturedSources[snapshot.candidate.id] {
                        matches.append(WindowSearchResult(id: source.id, title: source.title,
                            applicationName: source.applicationName, evidence: .image, excerpt: evidence,
                            score: -1, date: capturedAt, source: source, capsuleID: nil))
                    }
                } catch is CancellationError { return }
                catch { unavailable = true }
                guard accepts(generation) else { return }
            }
            guard accepts(generation) else { return }
            imageResults = matches; busy = false; imageSearching = false
            message = unavailable || snapshots.allSatisfy({ $0.image == nil })
                ? .windowSearchModelUnavailable : .windowSearchImageCaution
            rank()
        }
    }

    func clearCaptured() {
        if scope == .captured { results = []; selectedID = nil }
        cancelWork(); expiration?.cancel(); expiration = nil
        snapshots = []; capturedSources = [:]; capturedAt = nil; imageResults = []
        candidates = []; captureSelection = []; choosingCapture = false
        rank()
    }

    func cancelWork() {
        generation = UUID(); deadline?.cancel(); deadline = nil; work?.cancel(); work = nil; busy = false; imageSearching = false
        choosingCapture = false
    }

    func select(by offset: Int) {
        guard !results.isEmpty else { return }
        let index = selectedID.flatMap { id in results.firstIndex { $0.id == id } } ?? (offset > 0 ? -1 : 0)
        selectedID = results[(index + offset + results.count) % results.count].id
    }

    func activateSelection() {
        guard !choosingCapture, openedCapsule == nil, !busy else { return }
        guard let result = results.first(where: { $0.id == selectedID }) else { return }
        activate(result)
    }

    func activate(_ result: WindowSearchResult) {
        if let id = result.capsuleID {
            openedCapsule = capsules.capsules.first { $0.id == id }
            if openedCapsule == nil { message = .windowSearchStale; rank() }
            return
        }
        guard let source = result.source else { return }
        cancelWork(); busy = true
        let generation = self.generation
        setDeadline()
        work = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.activate(source)
                guard accepts(generation) else { return }
                activated?()
            } catch {
                guard accepts(generation) else { return }
                busy = false; message = .windowSearchStale
                // Selection consumes an AX session; refresh before another exact-window attempt.
            }
        }
    }

    func deleteOpenedCapsule() {
        guard let capsule = openedCapsule else { return }
        do { try capsules.delete(capsule.id); openedCapsule = nil; rank() }
        catch { message = .windowSearchDeleteFailed }
    }

    func stop() {
        stopped = true; clearCaptured(); ranking?.cancel(); ranking = nil; results = []; sources = []
        openedCapsule = nil; query = ""; close = nil; activated = nil
        let service = service
        Task { await service.stop() }
    }

    private func setDeadline() {
        deadline?.cancel()
        let generation = generation
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard let self, accepts(generation), busy else { return }
            cancelWork(); message = .windowSearchTimedOut
        }
    }

    private func accepts(_ id: UUID) -> Bool { !stopped && generation == id && !Task.isCancelled }
    private func invalidateImageSearch() {
        if imageSearching { cancelWork() }
        imageResults = []
    }

    /// Ranking receives bounded value copies and runs outside the UI actor, never during rendering.
    func rank() {
        ranking?.cancel()
        guard !stopped else { return }
        let query = query, scope = scope, sources = sources, snapshots = snapshots
        let owners = capturedSources, date = capturedAt, images = imageResults
        let saved = Array(capsules.capsules.prefix(SessionCapsuleDocument.capacity))
        ranking = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            let next = await WindowSearchIndex.results(query: query, scope: scope, sources: sources,
                snapshots: snapshots, owners: owners, date: date, saved: saved, images: images)
            guard !Task.isCancelled, let self, !stopped else { return }
            results = next
            if !next.contains(where: { $0.id == self.selectedID }) { selectedID = next.first?.id }
        }
    }
}
