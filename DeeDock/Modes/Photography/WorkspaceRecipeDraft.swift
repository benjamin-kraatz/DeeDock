import Foundation
import Observation

/// One deduplicated preparation choice and the ephemeral context that suggested it.
struct WorkspaceRecipeCaptureCandidate: Identifiable {
    let step: WorkspaceRecipeStep
    var isRunning = false
    var isPinned = false
    var windows: [WindowContextCandidate] = []

    var id: UUID { step.id }
}

/// An unsaved copy of the active layout. Editing or discarding it never changes the live modes.
@MainActor @Observable
final class WorkspaceRecipeDraft: Identifiable {
    let id = UUID()
    var mode: DockMode
    let sessionDisplays: [String: DockModeDisplayConfiguration]
    private(set) var candidates: [WorkspaceRecipeCaptureCandidate] = []
    private(set) var skippedPinCount = 0
    var windowStatus: WindowStatus = .loading

    enum WindowStatus: Equatable {
        case loading, available, permissionRequired, unavailable, empty

        var message: LocalizedStringResource {
            switch self {
            case .loading: .recipeSnapshotLoading
            case .available: .recipeSnapshotWindowsHelp
            case .permissionRequired: .recipeSnapshotPermission
            case .unavailable: .recipeSnapshotUnavailable
            case .empty: .recipeSnapshotNoWindows
            }
        }
    }

    /// Freezes pins, including session-only displays, before asynchronous window discovery starts.
    init(source: DockMode, sessionDisplays: [String: DockModeDisplayConfiguration],
         name: String, runningApplications: [ApplicationReference]) {
        mode = DockMode(name: name, appVisibility: source.appVisibility, displays: source.displays)
        self.sessionDisplays = sessionDisplays
        for application in runningApplications.sorted(by: {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }) {
            addApplication(application, isRunning: true)
        }
        let configurations = source.displays.merging(sessionDisplays) { persistent, _ in persistent }
        var seenFolders = Set<String>()
        for key in configurations.keys.sorted() {
            for pin in configurations[key]?.pins ?? [] {
                switch pin {
                case .application(let application):
                    addApplication(application, isPinned: true)
                case .folder(let folder):
                    guard seenFolders.insert(folder.url.standardizedFileURL.path).inserted else { continue }
                    let step = WorkspaceRecipeStep.resource(id: UUID(), bookmark: folder.bookmarkData, name: folder.name)
                    guard step.isPersistable else { skippedPinCount += 1; continue }
                    candidates.append(WorkspaceRecipeCaptureCandidate(step: step, isPinned: true))
                }
            }
        }
    }

    /// Merges running instances, window owners, and pins into a single app step.
    /// A pin's bookmark wins over an unscoped running-app reference.
    func addApplication(_ application: ApplicationReference, isRunning: Bool = false,
                        isPinned: Bool = false, window: WindowContextCandidate? = nil) {
        if let index = candidates.firstIndex(where: {
            if case .application(_, let existing) = $0.step { return existing.id == application.id }
            return false
        }) {
            let existing = candidates[index]
            let hasBookmark: Bool
            if case .application(_, let reference) = existing.step {
                hasBookmark = reference.bookmarkData != nil
            } else {
                hasBookmark = false
            }
            let step = isPinned && (application.bookmarkData != nil || !hasBookmark)
                ? WorkspaceRecipeStep.application(id: existing.id, application: application) : existing.step
            candidates[index] = WorkspaceRecipeCaptureCandidate(
                step: step, isRunning: existing.isRunning || isRunning, isPinned: existing.isPinned || isPinned,
                windows: existing.windows + (window.map { [$0] } ?? []))
        } else {
            candidates.append(WorkspaceRecipeCaptureCandidate(
                step: .application(id: UUID(), application: application), isRunning: isRunning,
                isPinned: isPinned, windows: window.map { [$0] } ?? []))
        }
    }

    /// Keeps overflow visible for selection instead of silently losing it during recipe sanitization.
    func selectInitialSteps() {
        mode.recipe = WorkspaceRecipe(steps: Array(candidates.map(\.step).prefix(WorkspaceRecipe.maximumStepCount)))
    }

    func isIncluded(_ candidate: WorkspaceRecipeCaptureCandidate) -> Bool {
        mode.recipe.steps.contains { $0.id == candidate.id }
    }

    func setIncluded(_ included: Bool, candidate: WorkspaceRecipeCaptureCandidate) {
        if included {
            guard !isIncluded(candidate), mode.recipe.steps.count < WorkspaceRecipe.maximumStepCount else { return }
            mode.recipe.steps.append(candidate.step)
        } else {
            mode.recipe.steps.removeAll { $0.id == candidate.id }
        }
    }
}
