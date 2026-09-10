import SwiftUI

/// Native launcher content. The containing dock window owns focus, frame morphing, and dismissal.
struct LauncherView: View {
    @Bindable var state: LauncherState
    /// The resting dock's own radius, so the surface starts the morph as exactly the shape the
    /// dock was drawing and the growth is the only thing that changes.
    var dockCornerRadius: CGFloat = 22
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @State private var columns = 1
    @State private var confirmClear = false

    var body: some View {
        let groups = state.usesFileActions || state.usesMixedResults ? [] : state.groups
        GeometryReader { geometry in
            // Presented, the panel's window is fixed at a frame that covers both ends of the morph
            // and the content lays out once at the rect it lands on. The morph is the glass rect
            // growing from the dock's rect to that one: nothing inside it ever changes position,
            // which is what kept the hosted controls trailing behind the old window resize.
            let presenting = state.contentRect != .zero
            let landing = presenting ? state.contentRect : CGRect(origin: .zero, size: geometry.size)
            let morphing = presenting && !state.expanded
            let rect = morphing ? state.dockRect : landing
            let radius: CGFloat = morphing
                ? min(dockCornerRadius, min(state.dockRect.width, state.dockRect.height) / 2)
                : 28
            ZStack(alignment: .topLeading) {
                panel(radius: radius)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                VStack(spacing: 16) {
                    LauncherSearchBar(
                        state: state,
                        searchFocused: $searchFocused
                    )
                    if !state.usesFileActions {
                        LauncherToolbar(state: state)
                    }
                    status
                    if state.usesFileActions {
                        LauncherFileInputSummaryView(state: state.fileActions)
                        LauncherFileActionsView(launcher: state)
                    } else if state.usesMixedResults {
                        LauncherMixedResultsView(launcher: state)
                    } else {
                        LauncherResultsView(state: state, columns: columns, groups: groups)
                    }
                    footer(count: resultCount(groups: groups))
                }
                .padding(20)
                .frame(width: landing.width, height: landing.height)
                .offset(x: landing.minX, y: landing.minY)
                .modifier(LauncherMorphFade(phase: presenting && !reduceMotion ? state.morph : 1))
                .allowsHitTesting(state.contentVisible)
                .accessibilityHidden(!state.contentVisible)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .mask(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: radius)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
            .onChange(of: landing.width, initial: true) { _, width in
                columns = max(1, Int((width - 56 + 12) / 148))
                state.navigationColumns = columns
            }
        }
        .onChange(of: state.contentVisible) { _, visible in searchFocused = visible }
        .onExitCommand { state.close?() }
        .onKeyPress(.downArrow) {
            state.moveSelection(by: state.usesGridNavigation ? columns : 1); return .handled
        }
        .onKeyPress(.upArrow) {
            state.moveSelection(by: state.usesGridNavigation ? -columns : -1); return .handled
        }
        .onKeyPress(.leftArrow) {
            guard !searchFocused else { return .ignored }
            state.moveSelection(by: -1); return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !searchFocused else { return .ignored }
            state.moveSelection(by: 1); return .handled
        }
        .confirmationDialog(Text(.launcherClearHistory), isPresented: $confirmClear) {
            Button(role: .destructive) { state.history.clear() } label: { Text(.launcherClearHistory) }
        } message: { Text(.launcherClearHistoryDetail) }
    }

    private func resultCount(groups: [LauncherState.Group]) -> Int {
        if state.usesFileActions { return state.fileActions.actions.count }
        if state.usesMixedResults { return state.search.results.count }
        return groups.reduce(0) { $0 + $1.applications.count }
    }

    /// The launcher's own material, drawn at whatever rect the morph currently holds.
    @ViewBuilder private func panel(radius: CGFloat) -> some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: radius).fill(Color(nsColor: .windowBackgroundColor))
        } else {
            RoundedRectangle(cornerRadius: radius).fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: radius))
        }
    }

    @ViewBuilder private var status: some View {
        if state.query.isEmpty, !state.usesMixedResults, state.catalog.suggestions.isActive {
            if state.catalog.suggestions.engineBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(.launcherSuggestionsEnginePreparing).font(.caption).foregroundStyle(.secondary)
                }
            } else if state.catalog.suggestions.engineUnavailable {
                Text(.launcherSuggestionsEngineUnavailable).font(.caption).foregroundStyle(.secondary)
            }
        }
        if let error = state.search.actionError {
            Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
        }
        if state.search.incompleteStores {
            Text(.unifiedStorageUnavailable).font(.caption).foregroundStyle(.secondary)
        }
        if state.usesMixedResults, let message = state.search.message {
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        if state.query.lowercased().trimmingCharacters(in: .whitespaces) == "do a barrel roll" {
            LauncherEasterEgg()
        }
        if let error = state.error {
            Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
        }
        if let message = state.robiMessage {
            HStack {
                Text(message).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { state.cancelRobi() } label: { Text(.launcherTextSearch) }
            }
        }
        if state.history.unreadable {
            HStack {
                Text(.launcherHistoryUnreadable).font(.caption).foregroundStyle(.secondary)
                Button { confirmClear = true } label: { Text(.launcherClearHistory) }
            }
        }
    }

    private func footer(count: Int) -> some View {
        HStack(spacing: 12) {
            HStack {
                if state.library.isLoading { ProgressView().controlSize(.mini) }
                Text(state.usesFileActions ? .launcherFileActionCount(count)
                     : state.usesMixedResults ? .unifiedResultCount(count) : .launcherResultCount(count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(.default, value: count)
            }
            .transition(.slide)
            .animation(.easeInOut(duration: 0.2), value: state.library.isLoading)

            if state.library.skippedDirectories > 0 {
                Image(systemName: "exclamationmark.triangle")
                    .help(Text(.launcherDiscoveryIncomplete)).accessibilityLabel(Text(.launcherDiscoveryIncomplete))
            }
            Spacer()
            Button { state.library.refresh(); state.search.refreshWindows() } label: { Image(systemName: "arrow.clockwise") }
                .disabled(state.library.isLoading || state.search.actionBusy || state.search.discovering)
                .accessibilityLabel(Text(.launcherRefresh))
                .symbolEffect(.rotate.byLayer, options: .nonRepeating, value: state.library.isLoading)
            Menu {
                Button { confirmClear = true } label: { Text(.launcherClearHistory) }
                Divider()
                // Opening Settings deliberately activates DDock; the launcher closes as focus leaves it.
                Button { openWindow.openDockSettings() } label: {
                    Label { Text(.launcherOpenSettings) } icon: { Image(systemName: "gearshape") }
                }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(Text(.launcherOptions))
        }
        .buttonStyle(.plain)
    }
}

/// An explicit search phrase reveals a short, non-flashing motion, with a static Reduce Motion alternative.
private struct LauncherEasterEgg: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rolled = false
    var body: some View {
        Label { Text(.launcherEasterEgg) } icon: {
            Image(systemName: "airplane").rotationEffect(.degrees(rolled && !reduceMotion ? 360 : 0))
        }
        .font(.headline).foregroundStyle(.tint)
        .onAppear { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) { rolled = true } }
    }
}
