import AppKit
import Observation

/// Runs one folder or Shortcut action after an explicit click. Detector evidence is never rewritten.
@MainActor @Observable
final class WindowWatchCompletionDispatcher {
    private(set) var phase: WindowWatchActionPhase = .idle
    private(set) var message: LocalizedStringResource?
    @ObservationIgnored private var gate: WindowWatchActionGate?
    @ObservationIgnored private var shortcut: ShortcutProcess?
    @ObservationIgnored private var folderTask: Task<Void, Never>?

    func bind(_ snapshot: WindowWatchRunSnapshot, outcome: WindowWatchRunOutcome) {
        let next = WindowWatchActionGate(runID: snapshot.runID, outcome: outcome, action: snapshot.configuration.completion)
        gate = next
        phase = next.phase
        if outcome != .detected { message = nil }
    }

    func mark(_ outcome: WindowWatchRunOutcome) {
        gate?.outcome = outcome
        if outcome != .detected {
            cancelWork()
            phase = gate?.phase ?? .idle
            message = nil
        }
    }

    var canOffer: Bool { gate?.canOffer == true }

    /// Starts the snapshot's action for `runID`. A second click or a stale run is ignored.
    @discardableResult
    func perform(runID: UUID, action: WindowWatchCompletionAction) -> Bool {
        guard var current = gate, current.begin(runID) else { return false }
        current.action = action
        gate = current
        phase = .running
        message = .watchActionRunning
        switch action {
        case .none:
            finish(success: false, message: .watchActionFailed)
        case .openFolder(let bookmark, _):
            openFolder(bookmark, runID: runID)
        case .runShortcut(let id, _):
            runShortcut(id, runID: runID)
        }
        return true
    }

    func cancel() {
        cancelWork()
        gate = nil
        phase = .idle
        message = nil
    }

    private func openFolder(_ bookmark: Data, runID: UUID) {
        folderTask?.cancel()
        folderTask = Task { [weak self] in
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                  relativeTo: nil, bookmarkDataIsStale: &stale)
                guard !stale else { throw CocoaError(.fileReadNoPermission) }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    throw CocoaError(.fileNoSuchFile)
                }
                try Task.checkCancellation()
                _ = try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
                await MainActor.run { self?.finish(success: true, runID: runID, message: .watchActionSucceeded) }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { self?.finish(success: false, runID: runID, message: .watchActionFolderMissing) }
            }
        }
    }

    /// Same CLI arguments as Action Tiles: identifier only, no captured pixels or OCR.
    private func runShortcut(_ id: UUID, runID: UUID) {
        let job = ShortcutProcess()
        shortcut = job
        job.start(arguments: ["run", id.uuidString]) { [weak self] result in
            guard let self else { return }
            shortcut = nil
            switch result {
            case .success:
                finish(success: true, runID: runID, message: .watchActionSucceeded)
            case .failure(let error):
                let detail = error is CancellationError
                    ? String(localized: .actionsCancelled)
                    : error.localizedDescription
                finish(success: false, runID: runID, message: .watchActionShortcutFailed(detail))
            }
        }
    }

    private func finish(success: Bool, runID: UUID? = nil, message: LocalizedStringResource) {
        if let runID, gate?.runID != runID { return }
        gate?.finish(success: success)
        phase = gate?.phase ?? (success ? .succeeded : .failed)
        self.message = message
    }

    private func cancelWork() {
        folderTask?.cancel()
        folderTask = nil
        shortcut?.cancel()
        shortcut = nil
    }
}
