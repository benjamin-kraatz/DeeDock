import SwiftUI

/// App-wide management for named configurations. Pin and visibility edits remain on their existing surfaces.
struct DockModesSettingsPane: View {
    let store: DockModesStore
    var activateMode: ((UUID) -> Bool)?
    var deleteMode: ((UUID) -> Bool)?
    var startFocus: ((DockMode) -> Void)?
    var canStartFocus = false
    @State private var draftName = ""
    @State private var namingAction: NamingAction?
    @State private var deletingMode: DockMode?

    private enum NamingAction: Identifiable {
        case create
        case rename(DockMode)
        var id: String {
            switch self { case .create: "create"; case .rename(let mode): "rename.\(mode.id)" }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
                SettingsCard(title: .dockModesActiveTitle, footnote: .dockModesHelp) {
                    SettingsRow(title: .dockModesActiveMode) {
                        Text(verbatim: store.activeMode.name).foregroundStyle(.secondary)
                    }
                    SettingsActionRow {
                        Button(.dockModesNew, systemImage: "plus", action: beginCreate)
                            .disabled(!store.canEdit)
                    }
                }
                SettingsCard(title: .dockModesConfigurationsTitle) {
                    SettingsStackedRow {
                        VStack(spacing: 0) {
                            ForEach(Array(store.modes.enumerated()), id: \.element.id) { index, mode in
                                if index > 0 { Divider().padding(.leading, 38) }
                                modeRow(mode, index: index)
                            }
                        }
                    }
                }
                if let error = store.errorMessage { SettingsErrorBanner(message: error) }
                if store.requiresReset {
                    SettingsCard(title: .dockModesRecoveryTitle, footnote: .dockModesRecoveryHelp) {
                        SettingsActionRow {
                            Button(.dockModesReset, systemImage: "arrow.counterclockwise", role: .destructive) { store.reset() }
                        }
                    }
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(Text(.dockModesTitle))
        .alert(namingTitle, isPresented: namingPresented) {
            TextField(String(localized: .dockModesNameField), text: $draftName)
            Button(.actionCancel, role: .cancel) { namingAction = nil }
            Button(.actionSave, action: saveName).disabled(!nameIsValid)
        } message: { Text(.dockModesNameHelp) }
        .alert(String(localized: .dockModesDeleteTitle), isPresented: deletePresented, presenting: deletingMode) { mode in
            Button(.dockModesDelete, role: .destructive) { _ = delete(mode.id) }
            Button(.actionCancel, role: .cancel) { deletingMode = nil }
        } message: { mode in
            Text(.dockModesDeleteMessage(modeName: mode.name))
        }
    }

    private func modeRow(_ mode: DockMode, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: mode.id == store.document.activeModeID ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(mode.id == store.document.activeModeID ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: mode.name)
                    .font(.body.weight(mode.id == store.document.activeModeID ? .semibold : .regular))
                Text(.dockModesDisplayCount(count: mode.displays.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            if let startFocus {
                Button(.focusStart, systemImage: "timer") { startFocus(mode) }
                    .labelStyle(.iconOnly).disabled(!canStartFocus)
                    .help(Text(.focusStartHelp))
            }
            Button(.dockModesActivate) { _ = activate(mode.id) }
                .disabled(!store.canEdit || mode.id == store.document.activeModeID)
            Menu {
                Button(.dockModesRename) { beginRename(mode) }
                Button(.dockModesDuplicate) {
                    _ = store.duplicate(mode.id)
                }
                Divider()
                Button(.dockModesMoveUp) { _ = store.move(mode.id, by: -1) }.disabled(index == 0)
                Button(.dockModesMoveDown) { _ = store.move(mode.id, by: 1) }.disabled(index == store.modes.count - 1)
                Divider()
                Button(.dockModesDelete, role: .destructive) { deletingMode = mode }.disabled(store.modes.count == 1)
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!store.canEdit)
            .accessibilityLabel(Text(.dockModesActions(modeName: mode.name)))
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private var namingPresented: Binding<Bool> {
        Binding(get: { namingAction != nil }, set: { if !$0 { namingAction = nil } })
    }
    private var deletePresented: Binding<Bool> {
        Binding(get: { deletingMode != nil }, set: { if !$0 { deletingMode = nil } })
    }
    private var namingTitle: String {
        switch namingAction {
        case .create: String(localized: .dockModesNewTitle)
        case .rename: String(localized: .dockModesRenameTitle)
        case nil: ""
        }
    }
    private var nameIsValid: Bool {
        let excluded: UUID?
        if case .rename(let mode) = namingAction { excluded = mode.id } else { excluded = nil }
        return DockModeNaming.isAvailable(draftName, in: store.modes, excluding: excluded)
    }
    private func beginCreate() {
        draftName = DockModeNaming.copyName(for: store.activeMode.name, in: store.modes)
        namingAction = .create
    }
    private func beginRename(_ mode: DockMode) { draftName = mode.name; namingAction = .rename(mode) }
    private func saveName() {
        switch namingAction {
        case .create:
            if let id = store.duplicateActive(named: draftName) { _ = activate(id) }
        case .rename(let mode): _ = store.rename(mode.id, to: draftName)
        case nil: break
        }
        namingAction = nil
    }
    private func activate(_ id: UUID) -> Bool { activateMode?(id) ?? store.activate(id) }
    private func delete(_ id: UUID) -> Bool { deleteMode?(id) ?? store.delete(id) }
}

#if DEBUG
#Preview("Dock Modes") {
    DockModesSettingsPane(store: DockModesPreview.store()).frame(width: 720, height: 620)
}
#Preview("Dock Modes — long names") {
    DockModesSettingsPane(store: DockModesPreview.store(longNames: true))
        .frame(width: 720, height: 620)
}
#Preview("Dock Modes — recovery") {
    DockModesSettingsPane(store: DockModesPreview.recoveryStore()).frame(width: 720, height: 620)
}

@MainActor
private enum DockModesPreview {
    static func store(longNames: Bool = false) -> DockModesStore {
        let store = DockModesStore(repository: nil)
        store.synchronize(displays: [], persistentDisplayIDs: [], primaryDisplayID: nil,
                          legacyPins: [:], legacyDefaultVisibility: .showAll,
                          legacyVisibilityOverrides: [:])
        _ = store.duplicateActive(named: longNames ? "A carefully arranged presentation workspace" : "Work")
        _ = store.duplicateActive(named: longNames ? "Writing without notifications or distractions" : "Writing")
        return store
    }

    static func recoveryStore() -> DockModesStore {
        let store = DockModesStore(repository: DockModesPreviewFailureRepository())
        store.synchronize(displays: [], persistentDisplayIDs: [], primaryDisplayID: nil,
                          legacyPins: [:], legacyDefaultVisibility: .showAll,
                          legacyVisibilityOverrides: [:])
        return store
    }
}

@MainActor
private final class DockModesPreviewFailureRepository: DockModesPersisting {
    func load() throws -> DockModesDocument? { throw CocoaError(.coderReadCorrupt) }
    func save(_ document: DockModesDocument) throws { throw CocoaError(.fileWriteUnknown) }
}
#endif
