import SwiftUI

/// Compact, keyboard-accessible rows for objects that need source and action labels as well as a title.
struct LauncherMixedResultsView: View {
    let launcher: LauncherState
    private var state: LauncherSearchState { launcher.search }

    var body: some View {
        let input = state.input(query: launcher.query, applications: launcher.library.applications)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if state.ranking {
                        ProgressView().controlSize(.small).padding()
                    } else if state.results.isEmpty {
                        ContentUnavailableView {
                            Label { Text(.launcherNoResults) } icon: { Image(systemName: "magnifyingglass") }
                        }
                    }
                    ForEach(state.visible) { result in
                        LauncherMixedResultRow(result: result, launcher: launcher).id(result.id)
                    }
                    if state.results.count > state.visible.count {
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
        .task(id: input) { await state.rank(input) }
    }
}

private struct LauncherMixedResultRow: View {
    let result: LauncherSearchResult
    let launcher: LauncherState
    private var state: LauncherSearchState { launcher.search }
    private var selected: Bool { state.selectedID == result.id }
    private var shortcutStatus: ActionTileStatus? {
        guard case .shortcut(let id) = result.id else { return nil }
        return state.actions?.statuses[id]
    }

    var body: some View {
        Button { state.activate(result) } label: {
            HStack(spacing: 12) {
                Image(systemName: result.kind.symbol).font(.title2).frame(width: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(result.title).font(.body.bold()).lineLimit(1)
                        Text(result.kind.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(result.source).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let shortcutStatus {
                        Text(shortcutStatus.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                Text(result.action).font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(result.unavailable || state.actionBusy || shortcutStatus?.busy == true)
        .contextMenu { LauncherMixedResultMenu(result: result, launcher: launcher) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(result.source)
    }
}

/// Used by both row context menus and the toolbar menu reachable with Tab from the search field.
struct LauncherMixedResultMenu: View {
    let result: LauncherSearchResult
    let launcher: LauncherState
    var body: some View {
        if let app = result.application {
            LauncherApplicationMenu(application: app, state: launcher)
        } else {
            Button { launcher.search.activate(result) } label: { Text(result.action) }
                .disabled(result.unavailable || launcher.search.actionBusy)
            if case .shelf = result.id {
                Button { launcher.search.activate(result, reveal: true) } label: { Text(.unifiedRevealFile) }
            }
            if case .window = result.id {
                Button { launcher.search.refreshWindows() } label: { Text(.unifiedRefreshWindows) }
            }
        }
    }
}

struct LauncherSearchControls: View {
    let launcher: LauncherState
    var body: some View {
        @Bindable var search = launcher.search
        HStack(spacing: 12) {
            Picker(selection: $search.kind) {
                ForEach(LauncherSearchKind.allCases) { kind in Text(kind.title).tag(kind) }
            } label: { Text(.unifiedTypeFilter) }
            .pickerStyle(.menu)
            .fixedSize()
            Spacer(minLength: 0)
            if launcher.usesMixedResults {
                Menu {
                    if let result = search.visible.first(where: { $0.id == search.selectedID }) ?? (search.selectedID == nil ? search.visible.first : nil) {
                        LauncherMixedResultMenu(result: result, launcher: launcher)
                    }
                } label: { Label { Text(.unifiedResultActions) } icon: { Image(systemName: "ellipsis.circle") } }
                .menuStyle(.borderlessButton).fixedSize()
            }
            Button { search.explicitSearch?() } label: {
                Label { Text(.unifiedCaptureRoute) } icon: { Image(systemName: "viewfinder") }
            }
            .buttonStyle(.borderless)
        }
        .font(.callout)
        .onChange(of: search.kind) {
            launcher.cancelRobi()
            launcher.keyboardNavigationActive = false
        }
    }
}
