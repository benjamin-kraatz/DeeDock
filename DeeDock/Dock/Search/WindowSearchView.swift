import SwiftUI

struct WindowSearchView: View {
    @Bindable var state: WindowSearchState
    @FocusState private var queryFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.openWindow) private var openWindow
    @State private var confirmsDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField(.windowSearchPlaceholder, text: $state.query)
                    .textFieldStyle(.roundedBorder).focused($queryFocused)
                    .onSubmit { state.activateSelection() }
                    .onKeyPress(.downArrow) { state.select(by: 1); return .handled }
                    .onKeyPress(.upArrow) { state.select(by: -1); return .handled }
                Button(.windowSearchRefresh) { state.refresh() }.disabled(state.busy)
            }
            Picker(.windowSearchScope, selection: $state.scope) {
                ForEach(WindowSearchScope.allCases) { scope in Text(scope.title).tag(scope) }
            }.pickerStyle(.segmented)
            Text(scopeHelp).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(.windowSearchChooseCapture) { state.chooseCapture() }.disabled(state.busy)
                if state.scope == .captured {
                    Button(.windowSearchImages) { state.searchImages() }
                        .disabled(state.busy || state.snapshots.isEmpty || state.query.isEmpty
                            || WindowSearchMatcher.wantsYesterday(state.query))
                    Button(.windowSearchClear) { state.clearCaptured() }
                        .disabled(state.snapshots.isEmpty && !state.busy)
                }
                Spacer()
                if state.busy {
                    ProgressView().controlSize(.small).accessibilityLabel(Text(.windowSearchWorking))
                    Button(.windowSearchCancel) { state.cancelWork() }
                }
            }
            if let message = state.message {
                Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if state.choosingCapture { capturePicker }
            else if let capsule = state.openedCapsule { capsuleDetail(capsule) }
            else { results }
            HStack {
                Text(.windowSearchKeyboardHelp).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(.windowPeekOpenSettings) { openWindow(id: "settings") }
            }
        }
        .padding(20)
        .frame(minWidth: 570, minHeight: 420)
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial))
        .onAppear { queryFocused = true }
        .onChange(of: state.scope) { state.openedCapsule = nil }
        .onExitCommand { state.close?() }
        .confirmationDialog(.windowSearchDeleteConfirmation, isPresented: $confirmsDelete) {
            Button(.windowSearchDeleteCapsule, role: .destructive) { state.deleteOpenedCapsule() }
        }
    }

    private var scopeHelp: LocalizedStringResource {
        switch state.scope {
        case .live: .windowSearchLiveHelp
        case .captured: .windowSearchRetention
        case .saved: .windowSearchSavedHelp
        }
    }

    private var capturePicker: some View {
        VStack(alignment: .leading) {
            Text(.windowSearchCaptureHelp).font(.callout)
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(state.candidates) { candidate in
                        Toggle(isOn: Binding(get: { state.captureSelection.contains(candidate.id) },
                                             set: { _ in state.toggleCapture(candidate) })) {
                            VStack(alignment: .leading) {
                                Text(verbatim: candidate.title ?? candidate.applicationName)
                                Text(verbatim: candidate.applicationName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(!state.captureSelection.contains(candidate.id)
                            && state.captureSelection.count >= WindowSearchMatcher.maximumCaptures)
                    }
                }
            }
            HStack {
                Button(.windowSearchCaptureSelected) { state.captureSelected() }
                    .disabled(state.captureSelection.isEmpty).buttonStyle(.borderedProminent)
                Button(.windowSearchCancel) { state.cancelWork() }
            }
        }
    }

    @ViewBuilder private var results: some View {
        if state.scope == .captured, let date = state.capturedAt {
            HStack { Text(.windowSearchCapturedAt); Text(date, format: .dateTime.year().month().day().hour().minute().second()) }
                .font(.caption)
            // Account for every selected window, including captures with no recognized text or image.
            ScrollView(.horizontal) {
                HStack {
                    ForEach(state.snapshots, id: \.candidate.id) { snapshot in
                        VStack(alignment: .leading) {
                            Text(verbatim: snapshot.candidate.applicationName + " · " + (snapshot.candidate.title ?? ""))
                            Text(snapshot.image == nil ? .windowSearchContentUnavailable
                                 : snapshot.recognizedText.isEmpty ? .windowSearchNoText : .windowSearchTextAvailable)
                        }.font(.caption).padding(6).background(.quaternary, in: .rect(cornerRadius: 6))
                    }
                }
            }.frame(maxHeight: 65)
        }
        if state.results.isEmpty {
            ContentUnavailableView {
                Label { Text(.windowSearchNoMatches) } icon: { Image(systemName: "magnifyingglass") }
            } description: {
                Text(WindowSearchMatcher.wantsYesterday(state.query) ? .windowSearchYesterdayHelp : .windowSearchNoMatchesHelp)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(state.results) { result in
                            WindowSearchResultView(result: result,
                                thumbnail: state.snapshots.first { $0.candidate.id == result.source?.candidate?.id }?.image,
                                selected: state.selectedID == result.id) {
                                    state.selectedID = result.id; state.activate(result)
                                }.id(result.id)
                        }
                    }
                }
                .onChange(of: state.selectedID) { if let id = state.selectedID { proxy.scrollTo(id) } }
            }
        }
    }

    private func capsuleDetail(_ capsule: SessionCapsule) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button(.windowSearchBack) { state.openedCapsule = nil }
                Text(verbatim: capsule.title).font(.title2)
                Text(capsule.createdAt, format: .dateTime.year().month().day().hour().minute())
                Text(.windowSearchCapsuleEvidence).font(.caption).foregroundStyle(.secondary)
                Text(verbatim: capsule.summary)
                Text(verbatim: capsule.note)
                ForEach(Array(capsule.unfinishedTasks.enumerated()), id: \.offset) { _, task in Text(verbatim: task) }
                ForEach(capsule.windows) { window in
                    Text(verbatim: window.applicationName + " · " + (window.windowTitle ?? ""))
                }
                Button(.windowSearchDeleteCapsule, role: .destructive) { confirmsDelete = true }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
