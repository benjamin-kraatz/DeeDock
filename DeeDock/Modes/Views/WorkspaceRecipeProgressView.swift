import AppKit
import SwiftUI

/// Per-step outcomes for one explicit Prepare workspace run.
struct WorkspaceRecipeProgressView: View {
    let coordinator: WorkspaceRecipeCoordinator
    var onOpenSettings: (() -> Void)?
    var previewReduceTransparency: Bool? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let run = coordinator.run {
                Text(.recipeProgressTitle(modeName: run.modeName))
                    .font(.headline)
                    .lineLimit(2)
                if let message = run.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(run.phase == .waiting || run.phase == .reported ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !run.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(run.steps) { step in
                            WorkspaceRecipeStepStatusRow(step: step, reduceMotion: reduceMotion)
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
                controls(run)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((previewReduceTransparency ?? reduceTransparency)
                    ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                    : AnyShapeStyle(.regularMaterial),
                    in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private func controls(_ run: WorkspaceRecipeRun) -> some View {
        HStack {
            if run.canCancel {
                Button(.actionCancel, role: .cancel) { coordinator.cancel() }
                    .help(Text(.recipeCancelHelp))
            }
            if run.canRetryOrSkip {
                Button(.recipeRetry) { coordinator.retryFailedStep() }
                Button(.recipeSkip) { coordinator.skipFailedStep() }
            }
            if let onOpenSettings, run.phase == .waiting || run.phase == .reported {
                Button(.recipeRepair) { onOpenSettings() }
            }
            if !run.phase.isActive {
                Button(.recipeDismiss) { coordinator.dismiss() }
            }
        }
    }
}

struct WorkspaceRecipeStepStatusRow: View {
    let step: WorkspaceRecipeStepProgress
    var reduceMotion = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusSymbol
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: step.title)
                    .lineLimit(2)
                Text(step.phase.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let detail = step.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: step.title))
        .accessibilityValue(Text(step.phase.title))
    }

    @ViewBuilder
    private var statusSymbol: some View {
        switch step.phase {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .running:
            if reduceMotion {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.tint)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        case .skipped:
            Image(systemName: "forward.circle")
                .foregroundStyle(.secondary)
        case .canceled:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview("Prepare workspace — running") {
    WorkspaceRecipeProgressView(coordinator: .preview(
        phase: .running,
        steps: [
            (.succeeded, "Xcode"),
            (.running, "DeeDock"),
            (.pending, "https://linear.app/d-zwei/issue/DEE-21"),
            (.pending, "Open project")
        ]
    ))
    .frame(width: 420)
}

#Preview("Prepare workspace — failed, reduced transparency") {
    WorkspaceRecipeProgressView(coordinator: .preview(
        phase: .waiting,
        message: .recipeStoppedOnFailure,
        steps: [
            (.succeeded, "Xcode"),
            (.failed, "Moved repo"),
            (.pending, "Open project")
        ]
    ), previewReduceTransparency: true)
    .frame(width: 420)
}

#Preview("Prepare workspace — canceled") {
    WorkspaceRecipeProgressView(coordinator: .preview(
        phase: .canceled,
        message: .recipeCanceledMessage,
        steps: [
            (.succeeded, "Xcode"),
            (.canceled, "DeeDock"),
            (.canceled, "Open project")
        ]
    ))
    .frame(width: 420)
}

private extension WorkspaceRecipeCoordinator {
    static func preview(phase: WorkspaceRecipeRunPhase, message: LocalizedStringResource? = nil,
                        steps: [(WorkspaceRecipeStepPhase, String)]) -> WorkspaceRecipeCoordinator {
        let coordinator = WorkspaceRecipeCoordinator(applications: WorkspaceRecipePreviewApplications(),
                                                     actions: ActionTilesController(defaults: UserDefaults(suiteName: "RecipeProgressPreview")!))
        coordinator.previewAssign(WorkspaceRecipeRun(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            modeID: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            modeName: "Work on DeeDock",
            phase: phase,
            steps: steps.map { phase, title in
                WorkspaceRecipeStepProgress(id: UUID(), title: title, symbolName: "app", phase: phase,
                                            detail: phase == .failed ? .recipeBookmarkStale : nil)
            },
            message: message
        ))
        return coordinator
    }

    func previewAssign(_ run: WorkspaceRecipeRun) {
        previewReplace(run)
    }
}

@MainActor
private final class WorkspaceRecipePreviewApplications: ApplicationServicing {
    func runningApplications() -> [ApplicationReference] { [] }
    func defaultFavorites() -> [ApplicationReference] { [] }
    func resolvedURL(for reference: ApplicationReference) -> URL? { reference.url }
    func icon(for url: URL?) -> NSImage { NSImage(systemSymbolName: "app", accessibilityDescription: nil)! }
    func pruneIcons(keeping urls: Set<URL>) {}
    func performPrimaryAction(_ reference: ApplicationReference) async throws -> ApplicationPrimaryActionOutcome { .opened }
    func open(_ reference: ApplicationReference) async throws {}
    func openDocuments(_ urls: [URL], with reference: ApplicationReference) async throws {}
}
#endif
