import SwiftUI

/// Save, apply, and manage named watches. Applying fills the form; Start remains a separate action.
struct WindowWatchPresetSetupView: View {
    @Bindable var session: WindowWatchSession
    var presets: WindowWatchPresetStore
    var actions: ActionTilesController?
    var tint: Color
    @State private var name = ""
    @State private var confirmsDelete: UUID?
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.watchPresetsHelp)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if presets.requiresReset {
                recovery
            } else {
                saveForm
                if let saveError {
                    Text(verbatim: saveError).font(.caption).foregroundStyle(.red)
                }
                if presets.presets.isEmpty {
                    Text(.watchPresetsEmpty).font(.caption).foregroundStyle(.secondary)
                } else {
                    lists
                }
            }
            if session.appliedPresetName != nil {
                Text(.watchPresetApplied)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { if name.isEmpty { name = defaultName } }
        .confirmationDialog(.watchPresetDeleteConfirm, isPresented: deletePresented, titleVisibility: .visible) {
            Button(.watchPresetDelete, role: .destructive) {
                if let id = confirmsDelete { try? presets.delete(id) }
                confirmsDelete = nil
            }
        } message: {
            Text(.watchPresetDeleteHelp)
        }
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = presets.error {
                Text(verbatim: error).font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(.watchPresetReset, role: .destructive) { try? presets.reset() }
            Text(.watchPresetResetHelp)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var saveForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(.watchPresetName, text: $name)
                .textFieldStyle(.roundedBorder)
            Text(.watchPresetNameHelp)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if canUpdate {
                    Button(.watchPresetUpdate) { persist(update: true) }
                        .disabled(!canSave)
                }
                Button(canUpdate ? .watchPresetSaveAs : .watchPresetSave) { persist(update: false) }
                    .disabled(!canSave || atCapacity)
            }
            if atCapacity {
                Text(.watchPresetLimit).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var lists: some View {
        VStack(alignment: .leading, spacing: 10) {
            let suggested = presets.suggestions(bundleIdentifier: session.bundleIdentifier, appName: session.appName)
            let others = presets.others(bundleIdentifier: session.bundleIdentifier, appName: session.appName)
            if !suggested.isEmpty {
                Text(.watchPresetSuggested).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(suggested) { row($0, suggested: true) }
            }
            if !others.isEmpty {
                Text(.watchPresetOthers).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(others, content: { row($0, suggested: false) })
            }
        }
    }

    private func row(_ preset: WindowWatchPreset, suggested: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: preset.name).font(.callout.weight(.medium))
                    Text(summary(preset)).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if suggested, let app = preset.configuration.appHint?.appName, !app.isEmpty {
                        Text(.watchPresetAppHint(appName: app)).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let app = preset.configuration.appHint?.appName, !app.isEmpty,
                       app.caseInsensitiveCompare(session.appName) != .orderedSame {
                        Text(.watchPresetHintMismatch(appName: app))
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Button(.watchPresetApply) { session.apply(preset); name = preset.name }
                Menu {
                    Button(.watchPresetDuplicate) { _ = try? presets.duplicate(preset.id) }
                        .disabled(presets.presets.count >= WindowWatchPresetDocument.capacity)
                    Button(.watchPresetDelete, role: .destructive) { confirmsDelete = preset.id }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .accessibilityLabel(Text(.watchPresetEdit))
            }
        }
        .padding(8)
        .background(session.appliedPresetID == preset.id ? tint.opacity(0.1) : Color.primary.opacity(0.04),
                    in: .rect(cornerRadius: 8))
    }

    private var canUpdate: Bool {
        session.appliedPresetID.flatMap { presets.preset($0) } != nil
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && session.draftConfiguration().isValid
            && !presets.requiresReset
    }

    private var atCapacity: Bool {
        !canUpdate && presets.presets.count >= WindowWatchPresetDocument.capacity
    }

    private var defaultName: String {
        let base = session.title.isEmpty ? session.appName : session.title
        return String(base.prefix(80))
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { confirmsDelete != nil }, set: { if !$0 { confirmsDelete = nil } })
    }

    private func persist(update: Bool) {
        do {
            var preset = WindowWatchPreset(
                id: update ? (session.appliedPresetID ?? UUID()) : UUID(),
                name: name,
                configuration: session.draftConfiguration(),
                createdAt: update ? (presets.preset(session.appliedPresetID ?? UUID())?.createdAt ?? Date()) : Date(),
                updatedAt: Date()
            )
            if !update { preset.id = UUID() }
            let saved = try presets.save(preset)
            session.appliedPresetID = saved.id
            session.appliedPresetName = saved.name
            name = saved.name
            saveError = nil
        } catch {
            saveError = String(localized: .watchPresetStorageFailed)
        }
    }

    private func summary(_ preset: WindowWatchPreset) -> LocalizedStringResource {
        if preset.configuration.usesPhrase {
            return .watchPresetConditionPhrase(phrase: preset.configuration.phrase)
        }
        switch preset.configuration.completion {
        case .none: return .watchPresetConditionChange
        case .openFolder(_, let folder): return .watchPresetFolderAction(folder: folder)
        case .runShortcut(_, let shortcut): return .watchPresetShortcutAction(shortcut: shortcut)
        }
    }
}

/// Shown on a running or finished watch so a later edit or delete can be seen without rewriting the snapshot.
struct WindowWatchPresetRunNote: View {
    let session: WindowWatchSession
    var presets: WindowWatchPresetStore
    @State private var confirmsDelete = false
    @State private var draftName = ""

    var body: some View {
        if let snapshot = session.runSnapshot, let id = snapshot.presetID {
            VStack(alignment: .leading, spacing: 6) {
                Text(.watchSnapshotNote)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let name = snapshot.presetName {
                    Text(verbatim: name).font(.callout.weight(.medium))
                }
                if let drift = session.presetDrift() {
                    Text(drift == .deleted ? .watchPresetDeletedDuringRun : .watchPresetEditedDuringRun)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let stored = presets.preset(id) {
                    TextField(.watchPresetName, text: $draftName)
                        .textFieldStyle(.roundedBorder)
                    Button(.watchPresetUpdate) { update(stored) }
                        .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(.watchPresetDelete, role: .destructive) { confirmsDelete = true }
                }
            }
            .onAppear { draftName = snapshot.presetName ?? presets.preset(id)?.name ?? "" }
            .confirmationDialog(.watchPresetDeleteConfirm, isPresented: $confirmsDelete) {
                Button(.watchPresetDelete, role: .destructive) { _ = try? presets.delete(id) }
            } message: {
                Text(.watchPresetDeleteHelp)
            }
        }
    }

    private func update(_ stored: WindowWatchPreset) {
        var next = stored
        next.name = String(draftName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        _ = try? presets.save(next)
    }
}

#if DEBUG
@MainActor private func previewPresetStore() -> WindowWatchPresetStore {
    let store = WindowWatchPresetStore(
        repository: WindowWatchPresetRepository(defaults: UserDefaults(suiteName: "WatchPresetPreview.\(UUID().uuidString)")!)
    )
    store.start()
    return store
}

#Preview("Preset setup") {
    WindowWatchPresetSetupView(
        session: WindowWatchSession(previewTitle: "Export – annual-report.pdf", message: .watchSetupHelp, setup: true),
        presets: previewPresetStore(), actions: nil, tint: .accentColor
    )
    .padding().frame(width: 460)
}
#endif
