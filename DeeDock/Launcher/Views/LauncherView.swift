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
    @State private var columns = 1
    @State private var confirmClear = false

    var body: some View {
        let groups = state.usesMixedResults ? [] : state.groups
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
                    header
                    LauncherSearchControls(launcher: state)
                    LauncherToolbar(state: state)
                    status
                    if state.usesMixedResults {
                        LauncherMixedResultsView(launcher: state)
                    } else {
                        LauncherResultsView(state: state, columns: columns, groups: groups)
                    }
                    footer(count: state.usesMixedResults ? state.search.results.count : groups.reduce(0) { $0 + $1.applications.count })
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

    /// The launcher's own material, drawn at whatever rect the morph currently holds.
    @ViewBuilder private func panel(radius: CGFloat) -> some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: radius).fill(Color(nsColor: .windowBackgroundColor))
        } else {
            RoundedRectangle(cornerRadius: radius).fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: radius))
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { searchFocused = true; state.keyboardNavigationActive = false } label: {
                Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.tint)
            }
            .buttonStyle(.plain).keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel(Text(.launcherSearch))
            TextField(text: $state.query, prompt: Text(.unifiedSearchPrompt)) {
                Text(.launcherSearch)
            }
            .textFieldStyle(.plain).font(.title2)
            .focused($searchFocused)
            .onSubmit { state.openSelection() }
            .autocorrectionDisabled()
            if !state.query.isEmpty {
                Button { state.query = ""; searchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel(Text(.launcherClearSearch))
            }
            Button { state.close?() } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .help(.launcherClose)
                .accessibilityLabel(Text(.launcherClose))
        }
        .padding(16)
        .background(.primary.opacity(0.045), in: .rect(cornerRadius: 18))
    }

    @ViewBuilder private var status: some View {
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
                Text(.launcherResultCount(count))
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
                .disabled(state.library.isLoading).accessibilityLabel(Text(.launcherRefresh))
                .symbolEffect(.rotate.byLayer, options: .nonRepeating, value: state.library.isLoading)
            Menu {
                Button { confirmClear = true } label: { Text(.launcherClearHistory) }
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
