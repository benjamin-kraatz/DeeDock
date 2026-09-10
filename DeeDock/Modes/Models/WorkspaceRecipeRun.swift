import Foundation

/// Transient per-step outcome. Never persisted and never replayed after launch.
enum WorkspaceRecipeStepPhase: Equatable {
    case pending, running, succeeded, failed, skipped, canceled

    var title: LocalizedStringResource {
        switch self {
        case .pending: .recipePending
        case .running: .recipeRunning
        case .succeeded: .recipeSucceeded
        case .failed: .recipeFailed
        case .skipped: .recipeSkipped
        case .canceled: .recipeCanceled
        }
    }

    var isFinished: Bool {
        switch self {
        case .succeeded, .skipped, .canceled: true
        case .pending, .running, .failed: false
        }
    }
}

/// One observed step in a single explicit prepare.
struct WorkspaceRecipeStepProgress: Identifiable, Equatable {
    let id: UUID
    let title: String
    let symbolName: String
    var phase: WorkspaceRecipeStepPhase
    var detail: LocalizedStringResource?
}

/// Lifetime of one Prepare workspace invocation.
enum WorkspaceRecipeRunPhase: Equatable {
    /// Reported a blocked switch or empty recipe without opening anything.
    case reported
    case running
    /// Stopped on a failed step and is waiting for an explicit retry or skip.
    case waiting
    case succeeded
    case canceled

    var isActive: Bool {
        switch self {
        case .running, .waiting: true
        case .reported, .succeeded, .canceled: false
        }
    }
}

/// In-memory record of one prepare. A restart leaves this empty on purpose.
struct WorkspaceRecipeRun: Identifiable, Equatable {
    let id: UUID
    let modeID: UUID
    let modeName: String
    var phase: WorkspaceRecipeRunPhase
    var steps: [WorkspaceRecipeStepProgress]
    var message: LocalizedStringResource?

    var failedIndex: Int? {
        steps.firstIndex { $0.phase == .failed }
    }

    var canCancel: Bool { phase.isActive }
    var canRetryOrSkip: Bool { phase == .waiting && failedIndex != nil }
}
