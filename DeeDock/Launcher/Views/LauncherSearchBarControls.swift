import SwiftUI

/// One search-field overflow for type, filters, layout, and file actions.
///
/// File-action mode keeps Choose Files and hides browse-only items. A discrete result type
/// replaces the app filter and location, sort, group, and layout pickers with result actions.
struct LauncherSearchBarOverflowMenu: View {
    @Bindable var state: LauncherState

    var body: some View {
        @Bindable var search = state.search
        Menu {
            if !state.usesFileActions {
                Picker(selection: $search.kind) {
                    ForEach(LauncherSearchKind.allCases) { kind in
                        Label {
                            Text(kind.title)
                        } icon: {
                            Image(systemName: kind.symbol)
                        }
                        .tag(kind)
                    }
                } label: {
                    Text(.unifiedTypeFilter)
                }
                if hasDiscreteKindSelected {
                    mixedResultActions
                } else {
                    appsFilter
                    locationSortGroup
                    layout
                }
                Divider()
            }
            chooseFiles
            if !state.usesFileActions {
                capture
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(.launcherSearchOverflow))
        .help(Text(.launcherSearchOverflowHelp))
        .onChange(of: search.kind) {
            state.cancelRobi()
            state.keyboardNavigationActive = false
        }
    }

    private var hasDiscreteKindSelected: Bool {
        state.search.kind != .all && state.search.kind != .application
    }

    private var appsFilter: some View {
        Picker(selection: $state.filter) {
            ForEach(LauncherFilter.allCases) { filter in
                Label {
                    Text(filter.title)
                } icon: {
                    Image(systemName: filter.symbol)
                }
                .tag(filter)
            }
        } label: {
            Text(.launcherFilter)
        }
    }

    @ViewBuilder private var locationSortGroup: some View {
        Picker(selection: $state.locationFilter) {
            ForEach(LauncherLocationFilter.allCases) { location in
                Text(location.title).tag(location)
            }
        } label: {
            Text(.launcherLocation)
        }
        Picker(selection: $state.sort) {
            ForEach(LauncherSort.allCases) { sort in
                Text(sort.title).tag(sort)
            }
        } label: {
            Text(.launcherSort)
        }
        Picker(selection: $state.grouping) {
            ForEach(LauncherGrouping.allCases) { group in
                Text(group.title).tag(group)
            }
        } label: {
            Text(.launcherGroup)
        }
    }

    private var layout: some View {
        Picker(selection: $state.layout) {
            ForEach(LauncherLayout.allCases) { layout in
                Label {
                    Text(layout.title)
                } icon: {
                    Image(systemName: layout.symbol)
                }
                .tag(layout)
            }
        } label: {
            Text(.launcherView)
        }
    }

    @ViewBuilder private var mixedResultActions: some View {
        if let result = mixedResultActionTarget {
            Divider()
            LauncherMixedResultMenu(result: result, launcher: state)
        }
    }

    private var chooseFiles: some View {
        Button {
            state.fileActions.chooseFiles()
        } label: {
            Label {
                Text(.launcherFileChooseFiles)
            } icon: {
                Image(systemName: "doc.badge.plus")
            }
        }
    }

    private var capture: some View {
        Button {
            state.search.explicitSearch?()
        } label: {
            Label {
                Text(.unifiedCaptureRoute)
            } icon: {
                Image(systemName: "camera.viewfinder")
            }
        }
    }

    private var mixedResultActionTarget: LauncherSearchResult? {
        guard let selectedID = state.search.selectedID else {
            return state.search.visible.first
        }

        return state.search.visible.first { $0.id == selectedID }
    }
}

/// Ask Robi, visible only for a trimmed nonempty query. Cancel stays available while a request runs.
struct LauncherRobiButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var state: LauncherState

    var body: some View {
        Group {
            if hasQuery {
                button
                    .transition(.blurReplace)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: hasQuery)
    }

    private var hasQuery: Bool {
        !state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var button: some View {
        Button {
            if state.robiBusy { state.cancelRobi() } else { state.askRobi() }
        } label: {
            HStack(spacing: 6) {
                if state.robiBusy {
                    ProgressView().controlSize(.mini).accessibilityHidden(true)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(state.robiBusy ? .launcherRobiCancel : .launcherAskRobi)
            }
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel(
            Text(state.robiBusy ? .launcherRobiCancel : .launcherAskRobi)
        )
        .disabled(!state.hasLocationMatchingApplications)
        .help(Text(.launcherRobiHelp))
    }
}
