import SwiftUI

/// Filters constrain both ordinary and Robi results; search relevance precedes the selected tie-break order.
struct LauncherToolbar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var state: LauncherState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                LauncherSearchKindPicker(launcher: state)
                kindActionsOrFilters
                Spacer(minLength: 8)
                if !hasDiscreteKindSelected { options }
                robi
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    LauncherSearchKindPicker(launcher: state)
                    kindActionsOrFilters
                }
                HStack {
                    if !hasDiscreteKindSelected { options }
                    Spacer()
                    robi
                }
            }
        }
    }
    
    private var hasDiscreteKindSelected: Bool {
        state.search.kind != .all
    }

    private var filters: some View {
        Picker(selection: $state.filter) {
            ForEach(LauncherFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        } label: {
            Text(.launcherFilter)
        }
        .labelsHidden()
        .controlSize(.large)
        .pickerStyle(.menu)
        .disabled(hasDiscreteKindSelected)
        .fixedSize()
    }
    
    private var kindActionsOrFilters: some View {
        ZStack(alignment: .leading) {
            if hasDiscreteKindSelected {
                mixedResultActions
                    .transition(kindActionTransition)
            } else {
                filters
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

    private var options: some View {
        HStack(spacing: 12) {
            Menu {
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
            .menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel(Text(.launcherSortAndGroup))
            Picker(selection: $state.layout) {
                ForEach(LauncherLayout.allCases) { layout in
                    Label {
                        Text(layout.title)
                    } icon: {
                        Image(systemName: layout.symbol)
                    }.tag(layout)
                }
            } label: {
                Text(.launcherView)
            }
            .labelsHidden()
            .pickerStyle(.tabs)
            .controlSize(.large)
            .fixedSize()
        }
    }

    private var mixedResultActionTarget: LauncherSearchResult? {
        guard let selectedID = state.search.selectedID else {
            return state.search.visible.first
        }

        return state.search.visible.first { $0.id == selectedID }
    }

    private var mixedResultActions: some View {
        Menu {
            if let result = mixedResultActionTarget {
                LauncherMixedResultMenu(
                    result: result,
                    launcher: state
                )
            }
        } label: {
            Label {
                Text(.unifiedResultActions)
            } icon: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.callout)
        .disabled(mixedResultActionTarget == nil)
    }

    private var robi: some View {
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
        .disabled(
            state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || state.library.applications.isEmpty
        )
        .controlSize(.large)
        .help(Text(.launcherRobiHelp))
    }
}
