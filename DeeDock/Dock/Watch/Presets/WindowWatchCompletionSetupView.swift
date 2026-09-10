import SwiftUI
import UniformTypeIdentifiers

/// Chooses the optional folder or Shortcut offered after a detected watch. Nothing runs from this form.
struct WindowWatchCompletionSetupView: View {
    @Binding var completion: WindowWatchCompletionAction
    var actions: ActionTilesController?
    var tint: Color
    @State private var choosingFolder = false
    @State private var pickingFolder = false
    @State private var pickingShortcut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.watchActionHelp)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                kindButton(.none, title: .watchActionNone, symbol: "minus.circle")
                kindButton(.folder, title: .watchActionFolder, symbol: "folder")
                kindButton(.shortcut, title: .watchActionShortcut, symbol: "bolt.square.fill")
            }
            switch kind {
            case .none:
                EmptyView()
            case .folder:
                if case .openFolder(_, let name) = completion { folderRow(name) }
                else { Button(.watchActionChooseFolder) { choosingFolder = true } }
            case .shortcut:
                shortcutRow(id: shortcutID, name: shortcutName)
            }
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            chooseFolder(result)
        }
    }

    private enum Kind { case none, folder, shortcut }

    private func kindButton(_ kind: Kind, title: LocalizedStringResource, symbol: String) -> some View {
        let selected = self.kind == kind
        return Button {
            switch kind {
            case .none:
                pickingFolder = false
                pickingShortcut = false
                completion = .none
            case .folder:
                pickingShortcut = false
                pickingFolder = true
                if case .openFolder = completion { break } else { choosingFolder = true }
            case .shortcut:
                pickingFolder = false
                pickingShortcut = true
            }
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? AnyShapeStyle(tint) : AnyShapeStyle(.primary))
        .background(selected ? tint.opacity(0.16) : Color.primary.opacity(0.06), in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(selected ? 0.5 : 0), lineWidth: 1) }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var kind: Kind {
        switch completion {
        case .openFolder: .folder
        case .runShortcut: .shortcut
        case .none: pickingShortcut ? .shortcut : (pickingFolder ? .folder : .none)
        }
    }

    private var shortcutID: UUID? {
        if case .runShortcut(let id, _) = completion { return id }
        return nil
    }

    private var shortcutName: String {
        if case .runShortcut(_, let name) = completion { return name }
        return ""
    }

    private func folderRow(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(.watchActionFolderChosen(name: name)).font(.callout)
            Button(.watchActionChangeFolder) { choosingFolder = true }
        }
    }

    private func shortcutRow(id: UUID?, name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.watchActionShortcutHelp)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actions {
                HStack {
                    Button(.watchActionLoadShortcuts) { actions.refresh() }
                        .disabled(actions.loading)
                    if actions.loading { ProgressView().controlSize(.small) }
                }
                if !actions.available.isEmpty {
                    Picker(.watchActionChooseShortcut, selection: shortcutBinding(actions: actions, current: id)) {
                        Text(.watchActionChooseShortcut).tag(Optional<UUID>.none)
                        ForEach(actions.available) { tile in
                            Text(verbatim: tile.name).tag(Optional(tile.id))
                        }
                    }
                    .labelsHidden()
                } else if actions.discovered, !actions.loading {
                    Text(.watchActionNoShortcuts)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = actions.error {
                    Text(verbatim: error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            } else {
                Text(verbatim: name).font(.callout)
            }
        }
        // Load when this row appears. Opening the form on No action must not start the Shortcuts CLI.
        .onAppear { actions?.ensureLoaded() }
    }

    private func shortcutBinding(actions: ActionTilesController, current: UUID?) -> Binding<UUID?> {
        Binding(
            get: { current },
            set: { id in
                guard let id, let tile = actions.available.first(where: { $0.id == id }) else { return }
                completion = .runShortcut(id: tile.id, name: tile.name)
            }
        )
    }

    private func chooseFolder(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return }
            let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
            guard data.count <= 65_536 else { return }
            completion = .openFolder(bookmark: data, name: url.lastPathComponent)
        } catch {
            return
        }
    }
}

/// Evidence stays in the result card. This view only offers or reports the configured action.
struct WindowWatchCompletionResultView: View {
    let session: WindowWatchSession
    var actions: ActionTilesController?
    var tint: Color

    var body: some View {
        if session.detected {
            VStack(alignment: .leading, spacing: 10) {
                if let snapshot = session.runSnapshot, snapshot.configuration.completion.isConfigured {
                    actionButton(snapshot.configuration.completion)
                }
                if let message = session.action.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(session.action.phase == .failed ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if session.action.phase == .failed {
                    repairControls
                }
            }
        }
    }

    @ViewBuilder private func actionButton(_ action: WindowWatchCompletionAction) -> some View {
        switch action {
        case .none:
            EmptyView()
        case .openFolder:
            Button(.watchActionOpenFolder, systemImage: "folder") { session.performCompletion() }
                .disabled(!session.action.canOffer)
        case .runShortcut:
            Button(.watchActionRunShortcut, systemImage: "bolt.square.fill") { session.performCompletion() }
                .disabled(!session.action.canOffer)
        }
    }

    @ViewBuilder private var repairControls: some View {
        WindowWatchCompletionSetupView(completion: Binding(
            get: { session.runSnapshot?.configuration.completion ?? session.completion },
            set: { session.repairCompletion($0) }
        ), actions: actions, tint: tint)
    }
}

#if DEBUG
#Preview("Completion setup") {
    @Previewable @State var completion = WindowWatchCompletionAction.none
    WindowWatchCompletionSetupView(completion: $completion, actions: nil, tint: .accentColor)
        .padding().frame(width: 460)
}
#endif
