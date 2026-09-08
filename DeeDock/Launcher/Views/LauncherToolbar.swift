import SwiftUI

/// Filters constrain both ordinary and Robi results; search relevance precedes the selected tie-break order.
struct LauncherToolbar: View {
    @Bindable var state: LauncherState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                if !state.usesMixedResults { filters }
                Spacer(minLength: 8)
                if !state.usesMixedResults { options }
                robi
            }
            VStack(alignment: .leading, spacing: 10) {
                if !state.usesMixedResults { filters }
                HStack {
                    if !state.usesMixedResults { options }
                    Spacer()
                    robi
                }
            }
        }
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
        .pickerStyle(.menu).fixedSize()
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
