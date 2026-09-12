import SwiftUI

/// Keeps every captured choice available, including choices beyond the persisted recipe's step limit.
struct WorkspaceRecipeCaptureCandidates: View {
    @Bindable var draft: WorkspaceRecipeDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.recipeSnapshotChoices).font(.headline)
            Text(.recipeSnapshotSelectionHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if draft.candidates.count > WorkspaceRecipe.maximumStepCount {
                Text(.recipeSnapshotOverflow).font(.callout).foregroundStyle(.orange)
            }
            if draft.skippedPinCount > 0 {
                Text(.recipeSnapshotSkippedPins).font(.callout).foregroundStyle(.orange)
            }
            ForEach(draft.candidates) { candidate in
                WorkspaceRecipeCaptureCandidateRow(candidate: candidate,
                    isIncluded: Binding(get: { draft.isIncluded(candidate) },
                                        set: { draft.setIncluded($0, candidate: candidate) }),
                    isAtLimit: draft.mode.recipe.steps.count >= WorkspaceRecipe.maximumStepCount)
            }
        }
    }
}

private struct WorkspaceRecipeCaptureCandidateRow: View {
    let candidate: WorkspaceRecipeCaptureCandidate
    @Binding var isIncluded: Bool
    let isAtLimit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $isIncluded) {
                Label {
                    Text(verbatim: candidate.step.title)
                } icon: {
                    Image(systemName: candidate.step.symbolName)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(!isIncluded && isAtLimit)
            HStack {
                if candidate.isRunning { Text(.recipeSnapshotRunning) }
                if candidate.isPinned { Text(.recipeSnapshotPinned) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !candidate.windows.isEmpty {
                DisclosureGroup {
                    ForEach(candidate.windows) { window in
                        Text(verbatim: window.title ?? String(localized: .recipeSnapshotUntitledWindow))
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                } label: {
                    Text(.recipeSnapshotWindows)
                        .font(.caption)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
