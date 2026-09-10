import SwiftUI

/// Searchable, keyboard-selectable actions for the current file batch.
struct LauncherFileActionsView: View {
    let launcher: LauncherState

    var body: some View {
        @Bindable var state = launcher.fileActions
        VStack(alignment: .leading, spacing: 10) {
                ForEach(LauncherFileActionKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            } label: {
                Text(.launcherFileKind)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            status
            ZStack {
                if state.visible.isEmpty {
                    if state.ranking {
                        ProgressView().controlSize(.small)
                    } else {
                        ContentUnavailableView {
                            Label {
                                Text(.launcherFileNoActions)
                            } icon: {
                                Image(systemName: "magnifyingglass")
                            }
                        } description: {
                            Text(.launcherFileNoActionsDetail)
                        }
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                if state.ranking { ProgressView().controlSize(.small).padding() }
                                ForEach(state.visible) { item in
                                    LauncherFileActionRow(item: item, launcher: launcher).id(item.id)
                                }
                                if state.actions.count > state.visible.count {
                                    Button { state.revealMore() } label: { Text(.unifiedShowMore) }
                                        .padding(10)
                                }
                            }
                            .padding(2)
                        }
                        .onChange(of: state.selectedID) { _, id in
                            if let id { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: launcher.query, initial: true) { _, query in
            state.filter(query: query)
        }
        .onChange(of: state.destinations.destinations.map(\.id), initial: false) { _, _ in
            state.refreshCatalog()
        }
    }

    @ViewBuilder private var status: some View {
        switch state.status {
        case .idle:
            EmptyView()
        case .pending:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(.launcherFilePending).font(.callout).foregroundStyle(.secondary)
            }
        case .completed:
            Text(.launcherFileCompleted).font(.callout).foregroundStyle(.secondary)
        case .failed(let message):
            Text(verbatim: message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
        case .partial(let message):
            Text(verbatim: message).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
        }
    }
}

private struct LauncherFileActionRow: View {
    let item: LauncherFileActionItem
    let launcher: LauncherState
    private var state: LauncherFileActionState { launcher.fileActions }
    private var selected: Bool { state.selectedID == item.id }
    @State private var icon: NSImage?
    private var shortcutStatus: ActionTileStatus? {
        guard case .shortcut(let id) = item.id else { return nil }
        return state.shortcutStatus(for: id)
    }

    var body: some View {
        Button {
            state.activate(item)
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable().scaledToFit()
                    } else {
                        Image(systemName: item.symbol).font(.title2)
                    }
                }
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(verbatim: item.title).font(.body.bold()).lineLimit(1)
                        Text(kindLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if !item.unsupportedNames.isEmpty {
                        Text(.launcherFileUnsupportedList(item.unsupportedNames.formatted()))
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                    if let shortcutStatus {
                        Text(shortcutStatus.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                Text(actionLabel).font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .task(id: item.application?.id) {
            icon = item.application.map { launcher.icon(for: $0) }
        }
        .disabled(item.unavailable || state.status.isPending || shortcutStatus?.busy == true)
        .accessibilityHint(Text(item.subtitle))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var kindLabel: LocalizedStringResource {
        switch item.id {
        case .openWith: .launcherFileKindApps
        case .shortcut: .launcherFileKindShortcuts
        case .copyTo, .chooseFolder: .launcherFileKindFolders
        }
    }

    private var actionLabel: LocalizedStringResource {
        switch item.id {
        case .openWith: .launcherFileOpenWithApp
        case .shortcut: .launcherFilePassToShortcut
        case .copyTo: .launcherFileCopyAction
        case .chooseFolder: .launcherFileChooseFolder
        }
    }
}

#if DEBUG
#Preview("File actions, empty") {
    let launcher = LauncherState(catalog: ApplicationCatalog(service: ApplicationService()))
    launcher.fileActions.adopt(.owned(
        DocumentResourceAccess([URL(fileURLWithPath: "/Preview/Notes.txt")],
                               startAccess: { _ in false }, stopAccess: { _ in }),
        source: .picker
    ))
    return LauncherFileActionsView(launcher: launcher)
        .padding()
        .frame(width: 720, height: 420)
}

#Preview("File actions, Reduce Motion") {
    let launcher = LauncherState(catalog: ApplicationCatalog(service: ApplicationService()))
    return LauncherFileActionsView(launcher: launcher)
        .padding()
        .frame(width: 720, height: 420)
        .environment(\.accessibilityReduceMotion, true)
}
#endif
