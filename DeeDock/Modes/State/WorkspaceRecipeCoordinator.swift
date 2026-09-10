import AppKit
import Observation

/// Owns one in-memory Prepare workspace run. Progress is never persisted or replayed.
@MainActor @Observable
final class WorkspaceRecipeCoordinator {
    private(set) var run: WorkspaceRecipeRun?
    @ObservationIgnored var didChange: (() -> Void)?
    @ObservationIgnored private let applications: any ApplicationServicing
    @ObservationIgnored private let actions: ActionTilesController
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var runningShortcutID: UUID?
    @ObservationIgnored private var snapshot: [WorkspaceRecipeStep] = []

    init(applications: any ApplicationServicing, actions: ActionTilesController) {
        self.applications = applications
        self.actions = actions
    }

    var isPreparing: Bool { run?.phase.isActive == true }

    /// Starts an explicit prepare. Ordinary mode switching never calls this.
    func prepare(mode: DockMode, canActivate: Bool, activate: @escaping (UUID) -> Bool) {
        if let run, run.isActive {
            didChange?()
            return
        }
        let recipe = mode.recipe.sanitized
        guard !recipe.isEmpty else {
            report(mode: mode, message: .recipeNoSteps)
            return
        }
        guard canActivate else {
            report(mode: mode, message: .recipePrepareBlocked)
            return
        }
        guard activate(mode.id) else {
            report(mode: mode, message: .recipePrepareBlocked)
            return
        }
        snapshot = recipe.steps
        run = WorkspaceRecipeRun(
            id: UUID(),
            modeID: mode.id,
            modeName: mode.name,
            phase: .running,
            steps: recipe.steps.map {
                WorkspaceRecipeStepProgress(id: $0.id, title: $0.title, symbolName: $0.symbolName,
                                            phase: .pending, detail: nil)
            },
            message: nil
        )
        didChange?()
        task?.cancel()
        task = Task { [weak self] in
            await self?.execute(from: 0)
        }
    }

    func retryFailedStep() {
        guard let index = run?.failedIndex, run?.phase == .waiting else { return }
        continueFrom(index)
    }

    func skipFailedStep() {
        guard let index = run?.failedIndex, run?.phase == .waiting else { return }
        updateStep(index) { step in
            step.phase = .skipped
            step.detail = nil
        }
        continueFrom(index + 1)
    }

    /// Stops work that has not finished. Already opened apps and Shortcut effects stay as they are.
    func cancel() {
        guard run?.phase.isActive == true else { return }
        task?.cancel()
        task = nil
        if let runningShortcutID { actions.cancel(runningShortcutID) }
        runningShortcutID = nil
        if var current = run {
            for index in current.steps.indices where !current.steps[index].phase.isFinished {
                current.steps[index].phase = .canceled
            }
            current.phase = .canceled
            current.message = .recipeCanceledMessage
            run = current
        }
        didChange?()
    }

    func dismiss() {
        guard run?.phase.isActive != true else { return }
        run = nil
        snapshot = []
        didChange?()
    }

    func stop() {
        cancel()
        run = nil
        snapshot = []
        didChange = nil
    }

#if DEBUG
    /// Injects a finished snapshot for SwiftUI previews. Never opens apps or runs Shortcuts.
    func previewReplace(_ run: WorkspaceRecipeRun) {
        self.run = run
    }
#endif

    private func report(mode: DockMode, message: LocalizedStringResource) {
        run = WorkspaceRecipeRun(id: UUID(), modeID: mode.id, modeName: mode.name,
                                 phase: .reported, steps: [], message: message)
        didChange?()
    }

    private func continueFrom(_ index: Int) {
        task?.cancel()
        mutate { current in
            current.phase = .running
            current.message = nil
            if current.steps.indices.contains(index) {
                current.steps[index].phase = .pending
                current.steps[index].detail = nil
            }
        }
        task = Task { [weak self] in
            await self?.execute(from: index)
        }
    }

    private func execute(from start: Int) async {
        var index = start
        while snapshot.indices.contains(index) {
            if Task.isCancelled {
                if run?.phase == .running { cancel() }
                return
            }
            let step = snapshot[index]
            updateStep(index) { progress in
                progress.phase = .running
                progress.detail = nil
            }
            let outcome = await perform(step)
            if Task.isCancelled {
                if run?.phase == .running { cancel() }
                return
            }
            switch outcome {
            case .succeeded(let detail):
                updateStep(index) { progress in
                    progress.phase = .succeeded
                    progress.detail = detail
                }
                index += 1
            case .failed(let detail):
                updateStep(index) { progress in
                    progress.phase = .failed
                    progress.detail = detail
                }
                mutate { current in
                    current.phase = .waiting
                    current.message = .recipeStoppedOnFailure
                }
                return
            }
        }
        mutate { current in
            current.phase = .succeeded
            current.message = .recipeCompleted
        }
    }

    private enum Outcome {
        case succeeded(LocalizedStringResource)
        case failed(LocalizedStringResource)
    }

    private func perform(_ step: WorkspaceRecipeStep) async -> Outcome {
        switch step {
        case .application(_, let application):
            return await openApplication(application)
        case .resource(_, let bookmark, _):
            return await openResource(bookmark)
        case .link(_, let raw):
            return openLink(raw)
        case .shortcut(_, let shortcutID, _):
            return await runShortcut(shortcutID)
        }
    }

    private func openApplication(_ application: ApplicationReference) async -> Outcome {
        guard applications.resolvedURL(for: application) != nil else {
            return .failed(.recipeAppMissing)
        }
        do {
            try Task.checkCancellation()
            try await applications.open(application)
            return .succeeded(.recipeAppOpened)
        } catch is CancellationError {
            return .failed(.recipeCanceled)
        } catch {
            return .failed(.recipeAppMissing)
        }
    }

    private func openResource(_ bookmark: Data) async -> Outcome {
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale else { return .failed(.recipeBookmarkStale) }
            let access = DocumentResourceAccess([url])
            defer { withExtendedLifetime(access) {} }
            guard FileManager.default.fileExists(atPath: url.path) else { return .failed(.recipeBookmarkStale) }
            try Task.checkCancellation()
            _ = try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
            return .succeeded(.recipeResourceOpened)
        } catch is CancellationError {
            return .failed(.recipeCanceled)
        } catch {
            return .failed(.recipeBookmarkStale)
        }
    }

    private func openLink(_ raw: String) -> Outcome {
        guard let url = WorkspaceRecipeLink.normalized(raw), NSWorkspace.shared.open(url) else {
            return .failed(.recipeURLInvalid)
        }
        return .succeeded(.recipeLinkOpened)
    }

    private func runShortcut(_ id: UUID) async -> Outcome {
        if actions.available.isEmpty == false || actions.tiles.isEmpty == false,
           actions.knowsShortcut(id) == false, !actions.available.isEmpty {
            return .failed(.recipeShortcutMissing)
        }
        runningShortcutID = id
        let result = await actions.runConfigured(id)
        runningShortcutID = nil
        switch result {
        case .success:
            return .succeeded(.recipeShortcutRan)
        case .failure(let error):
            if error is CancellationError { return .failed(.recipeCanceled) }
            return .failed(.recipeShortcutUncertain)
        }
    }

    private func updateStep(_ index: Int, _ body: (inout WorkspaceRecipeStepProgress) -> Void) {
        mutate { current in
            guard current.steps.indices.contains(index) else { return }
            body(&current.steps[index])
        }
    }

    private func mutate(_ body: (inout WorkspaceRecipeRun) -> Void) {
        guard var current = run else { return }
        body(&current)
        run = current
        didChange?()
    }
}

private extension WorkspaceRecipeRun {
    var isActive: Bool { phase.isActive }
}
