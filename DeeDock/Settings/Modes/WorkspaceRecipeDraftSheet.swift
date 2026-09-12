import SwiftUI

/// Reviews a snapshot in memory and persists a new mode only after an explicit Save.
struct WorkspaceRecipeDraftSheet: View {
    @Bindable var draft: WorkspaceRecipeDraft
    let store: DockModesStore
    var applications: (any ApplicationServicing)?
    var actions: ActionTilesController?
    var windowService: any WindowContextCapturing = ScreenCaptureWindowContextService()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(.recipeSnapshotTitle).font(.title2.bold())
            Text(.recipeSnapshotHelp)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(String(localized: .dockModesNameField), text: $draft.mode.name)
                .textFieldStyle(.roundedBorder)
            if !DockModeNaming.isAvailable(draft.mode.name, in: store.modes) {
                Text(.dockModesNameHelp).font(.caption).foregroundStyle(.orange)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if draft.windowStatus == .loading {
                        ProgressView().controlSize(.small)
                    }
                    Text(draft.windowStatus.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if draft.windowStatus != .loading {
                        WorkspaceRecipeCaptureCandidates(draft: draft)
                        Divider()
                        Text(.recipeSnapshotSteps).font(.headline)
                        WorkspaceRecipeEditor(mode: draft.mode, store: store, applications: applications,
                                              actions: actions, editDraft: { draft.mode.recipe = $0 })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = store.errorMessage {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Spacer()
                Button(.actionCancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(.recipeSnapshotSave) {
                    if store.saveRecipeDraft(draft) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 680)
        .task(id: draft.id) { await draft.discoverWindows(using: windowService) }
    }

    private var canSave: Bool {
        store.canEdit && draft.windowStatus != .loading && !draft.mode.recipe.isEmpty
            && draft.mode.recipe.isPersistable && DockModeNaming.isAvailable(draft.mode.name, in: store.modes)
    }
}

#if DEBUG
#Preview("Snapshot draft without window access") {
    WorkspaceRecipeDraftPreview.sheet(populated: false)
}

#Preview("Snapshot draft with edited steps, German") {
    WorkspaceRecipeDraftPreview.sheet(populated: true)
        .environment(\.locale, Locale(identifier: "de"))
}

@MainActor
private enum WorkspaceRecipeDraftPreview {
    static func sheet(populated: Bool) -> some View {
        let store = DockModesStore(repository: nil)
        store.synchronize(displays: [], persistentDisplayIDs: [], primaryDisplayID: nil,
                          legacyPins: [:], legacyDefaultVisibility: .showAll, legacyVisibilityOverrides: [:])
        let draft = store.makeRecipeDraft(runningApplications: [])
        // A completed sample avoids discovery, preference writes, and permission checks in previews.
        draft.windowStatus = populated ? .available : .permissionRequired
        if populated {
            draft.mode.name = "Arbeit am ausführlich benannten Beispielprojekt"
            draft.mode.recipe = WorkspaceRecipe(steps: [.link(id: UUID(), url: "https://example.com/project")])
        }
        return WorkspaceRecipeDraftSheet(draft: draft, store: store)
    }
}
#endif
