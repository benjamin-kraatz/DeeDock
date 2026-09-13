import SwiftUI

/// Compact browse chrome for the search field. File-action mode never hosts this cluster.
struct LauncherSearchBarBrowseControls: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var state: LauncherState
    /// When false, Ask Robi drops its title so the trailing cluster can shrink.
    var showsRobiTitle: Bool

    var body: some View {
        HStack(spacing: showsRobiTitle ? 8 : 4) {
            LauncherSearchKindPicker(launcher: state)
            kindActionsOrFilters
            if !hasDiscreteKindSelected {
                LauncherLocationSortGroupMenu(state: state)
                LauncherLayoutPicker(state: state)
            }
            LauncherRobiButton(state: state, showsTitle: showsRobiTitle)
        }
        .controlSize(showsRobiTitle ? .regular : .small)
    }

    private var hasDiscreteKindSelected: Bool {
        state.search.kind != .all && state.search.kind != .application
    }

    private var kindActionsOrFilters: some View {
        ZStack(alignment: .leading) {
            if hasDiscreteKindSelected {
                LauncherMixedResultActionsMenu(state: state)
                    .transition(kindActionTransition)
            } else {
                LauncherAppsFilterPicker(state: state)
                    .transition(kindActionTransition)
            }
        }
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.24),
            value: hasDiscreteKindSelected
        )
    }

    private var kindActionTransition: some Transition {
        .blurReplace
    }
}

/// Icon-only result-type menu. Full titles stay inside the menu.
struct LauncherSearchKindPicker: View {
    let launcher: LauncherState

    var body: some View {
        @Bindable var search = launcher.search
        Menu {
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
        } label: {
            Image(systemName: search.kind.barSymbol)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(.unifiedTypeFilter))
        .accessibilityValue(Text(search.kind.title))
        .help(Text(.unifiedTypeFilter))
        .onChange(of: search.kind) {
            launcher.cancelRobi()
            launcher.keyboardNavigationActive = false
        }
    }
}

/// Icon-only All / Running / Pinned / Recent menu. The icon follows the active filter.
struct LauncherAppsFilterPicker: View {
    @Bindable var state: LauncherState

    var body: some View {
        Menu {
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
        } label: {
            Image(systemName: state.filter.symbol)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(.launcherFilter))
        .accessibilityValue(Text(state.filter.title))
        .help(Text(.launcherFilter))
    }
}

/// Location, sort, and group pickers behind the existing options symbol.
struct LauncherLocationSortGroupMenu: View {
    @Bindable var state: LauncherState

    var body: some View {
        Menu {
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
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(.launcherSortAndGroup))
        .help(Text(.launcherSortAndGroup))
    }
}

/// Grid or list, icons only. Titles remain the accessibility names.
struct LauncherLayoutPicker: View {
    @Bindable var state: LauncherState

    var body: some View {
        Picker(selection: $state.layout) {
            ForEach(LauncherLayout.allCases) { layout in
                Image(systemName: layout.symbol)
                    .accessibilityLabel(Text(layout.title))
                    .tag(layout)
            }
        } label: {
            Text(.launcherView)
        }
        .labelsHidden()
        .pickerStyle(.tabs)
        .fixedSize()
        .accessibilityLabel(Text(.launcherView))
        .accessibilityValue(Text(state.layout.title))
        .help(Text(.launcherView))
    }
}

/// Ask Robi, visible only for a trimmed nonempty query. Cancel stays available while a request runs.
struct LauncherRobiButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var state: LauncherState
    var showsTitle: Bool

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
                if showsTitle {
                    Text(state.robiBusy ? .launcherRobiCancel : .launcherAskRobi)
                }
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

/// Keyboard-reachable actions for the selected mixed result, icon-only in the search bar.
struct LauncherMixedResultActionsMenu: View {
    @Bindable var state: LauncherState

    var body: some View {
        Menu {
            if let result = mixedResultActionTarget {
                LauncherMixedResultMenu(
                    result: result,
                    launcher: state
                )
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(mixedResultActionTarget == nil)
        .accessibilityLabel(Text(.unifiedResultActions))
        .help(Text(.unifiedResultActions))
    }

    private var mixedResultActionTarget: LauncherSearchResult? {
        guard let selectedID = state.search.selectedID else {
            return state.search.visible.first
        }

        return state.search.visible.first { $0.id == selectedID }
    }
}
