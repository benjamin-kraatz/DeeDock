import SwiftUI

/// Native launcher content. The containing dock window owns focus, frame morphing, and dismissal.
struct LauncherView: View {
    @Bindable var state: LauncherState
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columns = 1
    @State private var confirmClear = false

    var body: some View {
        let groups = state.groups
        GeometryReader { geometry in
            VStack(spacing: 16) {
                header
                LauncherToolbar(state: state)
                status
                LauncherResultsView(state: state, columns: columns, groups: groups)
                footer(count: groups.reduce(0) { $0 + $1.applications.count })
            }
            .padding(20)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .opacity(state.contentVisible ? 1 : 0)
            .allowsHitTesting(state.contentVisible)
            .accessibilityHidden(!state.contentVisible)
            .onChange(of: geometry.size.width, initial: true) { _, width in
                columns = max(1, Int((width - 56 + 12) / 148))
                state.navigationColumns = columns
            }
        }
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 28).fill(Color(nsColor: .windowBackgroundColor))
            } else {
                RoundedRectangle(cornerRadius: 28).fill(.clear)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
            }
        }
        .clipShape(.rect(cornerRadius: 28))
        .onChange(of: state.contentVisible) { _, visible in searchFocused = visible }
        .onExitCommand { state.close?() }
        .onKeyPress(.downArrow) {
            state.moveSelection(by: state.layout == .grid ? columns : 1); return .handled
        }
        .onKeyPress(.upArrow) {
            state.moveSelection(by: state.layout == .grid ? -columns : -1); return .handled
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

    private var header: some View {
        HStack(spacing: 14) {
            Button { searchFocused = true; state.keyboardNavigationActive = false } label: {
                Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.tint)
            }
            .buttonStyle(.plain).keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel(Text(.launcherSearch))
            TextField(text: $state.query, prompt: Text(.launcherSearchPrompt)) {
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
            Button { state.library.refresh() } label: { Image(systemName: "arrow.clockwise") }
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
