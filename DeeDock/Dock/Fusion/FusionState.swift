import Foundation
import CoreGraphics
import Observation

/// App-wide selection and draft ownership. Only explicit actions discover, capture, or generate.
/// An attempt ID rejects late results, and replacement work waits for cancellation to finish.
@MainActor @Observable
final class FusionState {
    private(set) var sources: [FusionSource] = []
    private(set) var candidates: [WindowContextCandidate] = []
    private(set) var activity: Activity?
    private(set) var error: String?
    private(set) var savedURL: URL?
    var operation: FusionOperation = .compare
    var instruction = ""
    var reviewed = false
    var draft: FusionDraft?
    var showingPicker = false
    private(set) var replacingID: UInt32?
    @ObservationIgnored private let contexts: any WindowContextCapturing
    @ObservationIgnored private let composer = FoundationModelsFusionComposer()
    @ObservationIgnored private let artifacts = FusionArtifactStore()
    @ObservationIgnored private let shelf: ShelfController
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var attempt = UUID()
    @ObservationIgnored private var expiresAt: Date?

    enum Activity { case discovering, capturing, generating, saving }
    var isBusy: Bool { activity != nil }
    var hasCapture: Bool { sources.count == 2 && sources.allSatisfy { $0.capturedAt != nil } }
    var hasTextInBoth: Bool { sources.count == 2 && sources.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    var canGenerate: Bool {
        hasCapture && reviewed && !isBusy && instruction.count <= 500
            && sources.allSatisfy { $0.text.count <= 6_000 }
            && (operation == .checklist ? sources.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } : hasTextInBoth)
    }

    init(shelf: ShelfController, contexts: any WindowContextCapturing = ScreenCaptureWindowContextService()) {
        self.shelf = shelf
        self.contexts = contexts
    }

    func select(_ candidate: WindowContextCandidate) {
        guard !isBusy, draft == nil, !sources.contains(where: { $0.id == candidate.id }) else { return }
        if let replacingID, let index = sources.firstIndex(where: { $0.id == replacingID }) {
            clearCapturedInput()
            sources[index] = FusionSource(candidate: candidate)
        } else {
            guard sources.count < 2 else { return }
            clearCapturedInput()
            sources.append(FusionSource(candidate: candidate))
        }
        replacingID = nil
        showingPicker = sources.count < 2
        error = nil
    }

    func remove(_ id: UInt32) {
        guard !isBusy, draft == nil else { return }
        clearCapturedInput()
        sources.removeAll { $0.id == id }
        replacingID = nil
    }

    func editSource(_ id: UInt32, text: String) {
        guard !isBusy, draft == nil, let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].text = String(text.prefix(6_000))
        sources[index].edited = true
        reviewed = false
    }

    func pick(replacing id: UInt32? = nil, matching summary: ApplicationWindowSummary? = nil) {
        guard !isBusy, draft == nil else { return }
        let replacement = id ?? (summary != nil ? replacingID : nil)
        if sources.count == 2 && replacement == nil {
            error = String(localized: .fusionSelectionFull)
            return
        }
        replacingID = replacement
        showingPicker = true
        run(.discovering) { [weak self] in
            guard let self else { return }
            let found = try await contexts.discover()
            try Task.checkCancellation()
            candidates = found
            if let summary {
                let matches = WindowThumbnailMatcher.matches(summaries: [summary], candidates: found.map {
                    WindowCaptureCandidate(id: $0.id, processIdentifier: $0.processIdentifier,
                                           title: $0.title, frame: $0.frame, isOnScreen: true)
                })
                // Never guess between two matching windows. The accessible picker resolves ambiguity.
                if let id = matches[summary.token], let candidate = found.first(where: { $0.id == id }) {
                    activity = nil
                    select(candidate)
                } else { error = String(localized: .fusionChooseExactWindow) }
            }
        }
    }

    func closePicker() {
        showingPicker = false
        replacingID = nil
    }

    func capture() {
        guard sources.count == 2, !isBusy, draft == nil else { return }
        clearCapturedInput()
        showingPicker = false
        let selected = sources.map(\.candidate)
        run(.capturing) { [weak self] in
            guard let self else { return }
            // Re-discover first so closed or no-longer-visible windows cannot be substituted.
            let available: [WindowContextCandidate]
            do { available = try await contexts.discover() }
            catch WindowContextCaptureError.noWindows { available = [] }
            try Task.checkCancellation()
            let valid = selected.filter { source in
                available.contains { $0.id == source.id && $0.processIdentifier == source.processIdentifier
                    && $0.bundleIdentifier == source.bundleIdentifier && $0.title == source.title }
            }
            let startedAt = Date()
            let snapshots = valid.isEmpty ? [] : try await contexts.capture(valid)
            try Task.checkCancellation()
            sources = selected.map { candidate in
                var source = FusionSource(candidate: candidate)
                source.capturedAt = startedAt
                guard let snapshot = snapshots.first(where: { $0.candidate.id == candidate.id }), snapshot.image != nil else {
                    source.captureState = .unavailable
                    return source
                }
                let text = snapshot.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                source.text = String(text.prefix(6_000))
                source.captureState = text.isEmpty ? .unreadable : text.count > 6_000 ? .truncated : .visibleText
                return source
            }
            if !hasTextInBoth { operation = .checklist }
            scheduleExpiry()
            // No snapshot or CGImage is retained after this operation returns.
        }
    }

    func generate() {
        expireIfNeeded()
        guard canGenerate else { return }
        let input = sources
        let selectedOperation = operation
        let userInstruction = instruction
        run(.generating) { [weak self] in
            guard let self else { return }
            let result = try await composer.compose(sources: input, operation: selectedOperation, instruction: userInstruction)
            try Task.checkCancellation()
            draft = result
            savedURL = nil
            clearCapturedInput()
        }
    }

    /// Saving has a short non-cancellable commit section after the file write. A failed Shelf
    /// insertion rolls back the new file and leaves the editable draft in place.
    func save() {
        guard !isBusy, let draft, draft.isValid, savedURL == nil else { return }
        error = nil
        activity = .saving
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await artifacts.write(draft)
                do {
                    guard try shelf.add([url]) == 0,
                          shelf.items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else {
                        throw FusionFailure.saveFailed
                    }
                    savedURL = url
                } catch {
                    do { try await artifacts.discard(url) }
                    catch {
                        // The file remains useful if rollback itself fails; show its location for recovery.
                        self.error = String(localized: .fusionSaveRecovery(path: url.path))
                    }
                    if self.error == nil { self.error = FusionFailure.saveFailed.localizedDescription }
                }
            } catch { self.error = FusionFailure.saveFailed.localizedDescription }
            activity = nil
            task = nil
        }
    }

    /// Cancels capture or generation while retaining completed reviewed text for an explicit retry.
    func cancelWork() {
        guard activity != .saving else { return }
        attempt = UUID()
        task?.cancel()
        deadline?.cancel(); deadline = nil
        activity = nil
        error = nil
    }

    func reset() {
        guard activity != .saving else { return }
        cancelWork()
        clearCapturedInput()
        sources = []; candidates = []; draft = nil; savedURL = nil
        instruction = ""; showingPicker = false; replacingID = nil
    }

    /// Escape/window close releases captured content but keeps selection and a generated draft.
    func suspend() {
        guard activity != .saving else { return }
        cancelWork()
        clearCapturedInput()
        candidates = []
        showingPicker = false
    }

    func expireIfNeeded() {
        if let expiresAt, Date() >= expiresAt {
            cancelWork()
            clearCapturedInput()
            error = String(localized: .fusionExpired)
        }
    }

    private func clearCapturedInput() {
        expiry?.cancel(); expiry = nil; expiresAt = nil
        reviewed = false
        for index in sources.indices {
            sources[index].text = ""
            sources[index].capturedAt = nil
            sources[index].captureState = .notCaptured
            sources[index].edited = false
        }
    }

    private func scheduleExpiry() {
        expiresAt = Date().addingTimeInterval(15 * 60)
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15 * 60))
            guard !Task.isCancelled else { return }
            self?.expireIfNeeded()
        }
    }

    private func run(_ activity: Activity, operation: @escaping @MainActor () async throws -> Void) {
        let previous = task
        cancelWork()
        let id = UUID()
        attempt = id
        self.activity = activity
        error = nil
        task = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, attempt == id else { return }
            do { try await operation() }
            catch is CancellationError { }
            catch {
                guard !Task.isCancelled, attempt == id else { return }
                if let capture = error as? WindowContextCaptureError {
                    self.error = (capture == .permissionRequired ? FusionFailure.captureDenied : .captureFailed).localizedDescription
                } else if let failure = error as? FusionFailure {
                    self.error = failure.localizedDescription
                } else {
                    self.error = (activity == .generating ? FusionFailure.invalidOutput : .captureFailed).localizedDescription
                }
            }
            guard !Task.isCancelled, attempt == id else { return }
            self.activity = nil
            deadline?.cancel(); deadline = nil
            task = nil
        }
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard let self, !Task.isCancelled, attempt == id else { return }
            cancelWork()
            error = FusionFailure.timeout.localizedDescription
        }
    }
}

#if DEBUG
extension FusionState {
    /// Deterministic preview state; does not discover windows or touch stored preferences.
    ///
    /// `captured: false` shows the first step instead: one filled slot, one waiting, picker open.
    static func preview(captured: Bool = true, failedSave: Bool = false) -> FusionState {
        let state = FusionState(shelf: ShelfController())
        let date = Date(timeIntervalSince1970: 1_783_000_000)
        state.sources = (1...2).map { index in
            var source = FusionSource(candidate: WindowContextCandidate(
                id: UInt32(index), processIdentifier: 42, applicationName: "Preview App",
                bundleIdentifier: nil, title: "Draft \(index)",
                frame: CGRect(x: 0, y: 0, width: 800, height: 600)))
            guard captured else { return source }
            source.capturedAt = date
            source.captureState = index == 1 ? .visibleText : .truncated
            source.text = "Review the draft. Confirm the proposed schedule with the team."
            return source
        }
        if !captured {
            state.sources = Array(state.sources.prefix(1))
            state.candidates = (10...14).map { index in
                WindowContextCandidate(id: UInt32(index), processIdentifier: pid_t(index),
                                       applicationName: "Preview App \(index - 9)",
                                       bundleIdentifier: nil, title: "Visible window \(index - 9)",
                                       frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            }
            state.showingPicker = true
        }
        if failedSave {
            state.draft = FusionDraft(title: "Review schedule changes",
                body: "The visible drafts use different dates. Confirm which date applies. [1, 2]",
                operation: .compare, sources: state.sources.map(FusionProvenance.init), generatedAt: date)
            state.error = FusionFailure.saveFailed.localizedDescription
        }
        return state
    }
}
#endif
