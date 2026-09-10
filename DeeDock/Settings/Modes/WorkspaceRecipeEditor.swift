import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Creates and repairs an optional mode recipe. Saving writes configuration only.
struct WorkspaceRecipeEditor: View {
    let mode: DockMode
    let store: DockModesStore
    var applications: (any ApplicationServicing)?
    var actions: ActionTilesController?
    var prepare: (() -> Void)?
    var canPrepare = false
    @State private var isPicking = false
    @State private var pickerKind = ResourcePicker.resource
    @State private var replacingStepID: UUID?
    @State private var linkDraft = ""
    @State private var addingLink = false
    @State private var editorError: LocalizedStringResource?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.recipeEditorHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if mode.recipe.isEmpty {
                Text(.recipeEmpty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(mode.recipe.steps.enumerated()), id: \.element.id) { index, step in
                        if index > 0 { Divider() }
                        stepRow(step, index: index)
                    }
                }
            }
            if let editorError {
                Text(editorError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            addButtons
            if let prepare {
                Button(.recipeTitle, systemImage: "briefcase") { prepare() }
                    .disabled(!canPrepare || mode.recipe.isEmpty || !store.canEdit)
                    .help(Text(.recipePrepareHelp))
            }
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: pickerKind == .application ? [.application] : [.item],
                      allowsMultipleSelection: false) { result in
            switch pickerKind {
            case .application: addApplications(result)
            case .resource: addResources(result)
            }
        }
        .alert(String(localized: .recipeAddLink), isPresented: $addingLink) {
            TextField(String(localized: .recipeLinkField), text: $linkDraft)
            Button(.actionCancel, role: .cancel) { addingLink = false; replacingStepID = nil }
            Button(.actionSave, action: saveLink)
        } message: {
            Text(.recipeLinkPrompt)
        }
    }

    private func stepRow(_ step: WorkspaceRecipeStep, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: step.symbolName)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: step.title)
                        .lineLimit(2)
                    Text(kindTitle(step))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let issue = issue(for: step) {
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Button(.dockModesMoveUp, systemImage: "arrow.up") { move(step.id, by: -1) }
                    .labelStyle(.iconOnly)
                    .disabled(index == 0 || !store.canEdit)
                Button(.dockModesMoveDown, systemImage: "arrow.down") { move(step.id, by: 1) }
                    .labelStyle(.iconOnly)
                    .disabled(index == mode.recipe.steps.count - 1 || !store.canEdit)
                Menu {
                    Button(.recipeRepair) { beginRepair(step) }
                    Button(.recipeRemove, role: .destructive) { remove(step.id) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .disabled(!store.canEdit)
                .accessibilityLabel(Text(.recipeStepActions(stepName: step.title)))
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private var addButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                addMenu
                Spacer(minLength: 0)
            }
            addMenu
        }
        .disabled(!store.canEdit || mode.recipe.steps.count >= WorkspaceRecipe.maximumStepCount)
    }

    private var addMenu: some View {
        Menu(.recipeAdd) {
            Button(.recipeAddApp) { beginPicking(.application) }
            if !pinnedApplications.isEmpty {
                Menu(.recipeAddPinnedApp) {
                    ForEach(pinnedApplications, id: \.id) { application in
                        Button(application.name) { append(.application(id: UUID(), application: application)) }
                    }
                }
            }
            Button(.recipeAddFile) { beginPicking(.resource) }
            Button(.recipeAddLink) { linkDraft = "https://"; addingLink = true }
            if let actions {
                Menu(.recipeAddShortcut) {
                    Button(.watchActionLoadShortcuts) { actions.refresh() }
                    if actions.loading {
                        Text(.actionsRunning)
                    }
                    ForEach(shortcutChoices(actions)) { tile in
                        Button(tile.name) {
                            replaceOrAppend(.shortcut(id: replacingStepID ?? UUID(), shortcutID: tile.id, name: tile.name))
                            replacingStepID = nil
                        }
                    }
                }
            }
        }
    }

    private enum ResourcePicker { case application, resource }

    private func beginPicking(_ kind: ResourcePicker) {
        pickerKind = kind
        isPicking = true
    }

    private func kindTitle(_ step: WorkspaceRecipeStep) -> LocalizedStringResource {
        switch step {
        case .application: .recipeKindApp
        case .resource: .recipeKindFile
        case .link: .recipeKindLink
        case .shortcut: .recipeKindShortcut
        }
    }

    private func issue(for step: WorkspaceRecipeStep) -> WorkspaceRecipeIssue? {
        step.issue(
            resolvedURL: { applications?.resolvedURL(for: $0) ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier ?? "") },
            knowsShortcut: { actions?.knowsShortcut($0) == true },
            shortcutsEnumerated: actions?.available.isEmpty == false
        )
    }

    private var pinnedApplications: [ApplicationReference] {
        var seen = Set<String>()
        var result: [ApplicationReference] = []
        for configuration in mode.displays.values {
            for pin in configuration.pins {
                guard let application = pin.application, seen.insert(application.id).inserted else { continue }
                result.append(application)
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func shortcutChoices(_ actions: ActionTilesController) -> [ActionTile] {
        var seen = Set<UUID>()
        return (actions.tiles + actions.available).filter { seen.insert($0.id).inserted }
    }

    private func beginRepair(_ step: WorkspaceRecipeStep) {
        replacingStepID = step.id
        switch step {
        case .application: beginPicking(.application)
        case .resource: beginPicking(.resource)
        case .link:
            if case .link(_, let url) = step { linkDraft = url }
            addingLink = true
        case .shortcut:
            actions?.refresh()
        }
    }

    private func addApplications(_ result: Result<[URL], Error>) {
        defer { replacingStepID = nil }
        do {
            let imported = try DockApplicationImporter.read(try result.get(),
                                                            excluding: Bundle.main.bundleIdentifier ?? "")
            guard let application = imported.first else { return }
            replaceOrAppend(.application(id: replacingStepID ?? UUID(), application: application))
        } catch is CancellationError {
            return
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSUserCancelledError { return }
            editorError = .recipeAppMissing
        }
    }

    private func addResources(_ result: Result<[URL], Error>) {
        defer { replacingStepID = nil }
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
            guard data.count <= WorkspaceRecipe.maximumBookmarkBytes else {
                editorError = .recipeBookmarkStale
                return
            }
            replaceOrAppend(.resource(id: replacingStepID ?? UUID(), bookmark: data, name: url.lastPathComponent))
        } catch is CancellationError {
            return
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSUserCancelledError { return }
            editorError = .recipeBookmarkStale
        }
    }

    private func saveLink() {
        guard let url = WorkspaceRecipeLink.normalized(linkDraft) else {
            editorError = .recipeURLInvalid
            return
        }
        replaceOrAppend(.link(id: replacingStepID ?? UUID(), url: url.absoluteString))
        addingLink = false
        replacingStepID = nil
    }

    private func replaceOrAppend(_ step: WorkspaceRecipeStep) {
        var steps = mode.recipe.steps
        if let replacingStepID, let index = steps.firstIndex(where: { $0.id == replacingStepID }) {
            steps[index] = step
        } else {
            append(step)
            return
        }
        commit(WorkspaceRecipe(steps: steps))
    }

    private func append(_ step: WorkspaceRecipeStep) {
        guard mode.recipe.steps.count < WorkspaceRecipe.maximumStepCount else {
            editorError = .recipeMaxSteps
            return
        }
        commit(WorkspaceRecipe(steps: mode.recipe.steps + [step]))
    }

    private func move(_ id: UUID, by distance: Int) {
        var steps = mode.recipe.steps
        guard let index = steps.firstIndex(where: { $0.id == id }),
              steps.indices.contains(index + distance) else { return }
        steps.swapAt(index, index + distance)
        commit(WorkspaceRecipe(steps: steps))
    }

    private func remove(_ id: UUID) {
        commit(WorkspaceRecipe(steps: mode.recipe.steps.filter { $0.id != id }))
    }

    private func commit(_ recipe: WorkspaceRecipe) {
        editorError = nil
        _ = store.updateRecipe(mode.id, recipe)
    }
}

#if DEBUG
#Preview("Recipe editor — empty") {
    WorkspaceRecipeEditor(mode: DockMode(name: "Work"), store: DockModesPreviewStore.make())
        .padding()
        .frame(width: 560)
}

#Preview("Recipe editor — populated") {
    let app = ApplicationReference(bundleIdentifier: "com.apple.dt.Xcode",
                                   url: URL(fileURLWithPath: "/Applications/Xcode.app"), name: "Xcode")
    let mode = DockMode(name: "Work on DeeDock", recipe: WorkspaceRecipe(steps: [
        .application(id: UUID(), application: app),
        .link(id: UUID(), url: "https://linear.app/d-zwei/issue/DEE-21"),
        .shortcut(id: UUID(), shortcutID: UUID(), name: "Open project")
    ]))
    WorkspaceRecipeEditor(mode: mode, store: DockModesPreviewStore.make(mode: mode),
                          actions: ActionTilesController(defaults: UserDefaults(suiteName: "RecipeEditorPreview")!))
        .padding()
        .frame(width: 560)
}

@MainActor
private enum DockModesPreviewStore {
    static func make(mode: DockMode? = nil) -> DockModesStore {
        let store = DockModesStore(repository: nil)
        store.synchronize(displays: [], persistentDisplayIDs: [], primaryDisplayID: nil,
                          legacyPins: [:], legacyDefaultVisibility: .showAll,
                          legacyVisibilityOverrides: [:])
        if let mode {
            _ = store.duplicateActive(named: mode.name)
            if let id = store.modes.first(where: { $0.name == mode.name })?.id {
                _ = store.updateRecipe(id, mode.recipe)
            }
        }
        return store
    }
}
#endif
