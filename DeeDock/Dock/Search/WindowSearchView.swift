import SwiftUI

/// The search window: a fixed header, one content area per mode, and a fixed keyboard footer.
///
/// Modes are exclusive by design. Choosing windows to capture and reading a saved capsule both
/// replace the result list so the user is never looking at two kinds of evidence at once.
struct WindowSearchView: View {
    @Bindable var state: WindowSearchState
    @FocusState private var queryFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.openWindow) private var openWindow
    @State private var confirmsDelete = false

    var body: some View {
        VStack(spacing: 0) {
            if !state.choosingCapture && state.openedCapsule == nil {
                WindowSearchHeaderView(state: state, queryFocused: $queryFocused)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            WindowSearchFooterView { openWindow.openDockSettings() }
        }
        .frame(minWidth: WindowSearchStyle.minimumSize.width, minHeight: WindowSearchStyle.minimumSize.height)
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                       : AnyShapeStyle(.regularMaterial))
        .onAppear { queryFocused = true }
        .onChange(of: state.scope) { state.openedCapsule = nil; queryFocused = true }
        .onExitCommand { state.close?() }
        .confirmationDialog(.windowSearchDeleteConfirmation, isPresented: $confirmsDelete) {
            Button(.windowSearchDeleteCapsule, role: .destructive) { state.deleteOpenedCapsule() }
        }
    }

    @ViewBuilder private var content: some View {
        if state.choosingCapture {
            WindowSearchCapturePickerView(state: state)
        } else if let capsule = state.openedCapsule {
            WindowSearchCapsuleDetailView(capsule: capsule, onBack: { state.openedCapsule = nil },
                                          onDelete: { confirmsDelete = true })
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if state.scope == .captured && !state.snapshots.isEmpty {
                    WindowSearchCapturedBarView(state: state)
                        .padding(.horizontal, WindowSearchStyle.contentPadding)
                        .padding(.top, state.message == nil ? 12 : 0)
                }
                results
            }
        }
    }

    @ViewBuilder private var results: some View {
        if state.results.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(state.results) { result in
                            WindowSearchResultView(result: result,
                                thumbnail: state.snapshots.first { $0.candidate.id == result.source?.candidate?.id }?.image,
                                selected: state.selectedID == result.id) {
                                    state.selectedID = result.id
                                    state.activate(result)
                                }
                                .id(result.id)
                        }
                    }
                    .padding(.horizontal, WindowSearchStyle.contentPadding)
                    .padding(.vertical, 10)
                }
                .onChange(of: state.selectedID) { if let id = state.selectedID { proxy.scrollTo(id) } }
            }
        }
    }

    /// Empty results mean different things per scope: nothing captured yet, nothing saved yet, or a
    /// query that matched nothing. Each case offers the action that resolves it.
    @ViewBuilder private var emptyState: some View {
        if state.scope == .captured && state.snapshots.isEmpty {
            ContentUnavailableView {
                Label { Text(.windowSearchNoCapture) } icon: { Image(systemName: "text.viewfinder") }
            } description: {
                Text(.windowSearchCaptureHelp)
            } actions: {
                Button(.windowSearchChooseCapture) { state.chooseCapture() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.busy)
            }
        } else if state.scope == .saved && state.capsules.capsules.isEmpty {
            ContentUnavailableView {
                Label { Text(.windowSearchNoCapsules) } icon: { Image(systemName: "archivebox") }
            } description: {
                Text(.windowSearchSavedHelp)
            }
        } else {
            ContentUnavailableView {
                Label { Text(.windowSearchNoMatches) } icon: { Image(systemName: "magnifyingglass") }
            } description: {
                Text(WindowSearchMatcher.wantsYesterday(state.query)
                     ? .windowSearchYesterdayHelp : .windowSearchNoMatchesHelp)
            }
        }
    }
}
