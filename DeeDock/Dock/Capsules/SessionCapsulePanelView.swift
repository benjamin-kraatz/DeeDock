import SwiftUI

/// Deliberate checkpoint flow: choose visible windows, review an editable draft, then save.
struct SessionCapsulePanelView: View {
    let state: SessionCapsulePanelState
    var forceOpaqueBackground = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = state.error {
                errorBanner(error)
                Divider()
            }
            content
        }
        .dockPopoverChrome(state.chrome, opaque: reduceTransparency || forceOpaqueBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.capsulesName))
    }

    private var header: some View {
        HStack(spacing: 8) {
            if state.page != .collection {
                Button { state.back() } label: { Image(systemName: "chevron.backward") }
                    .buttonStyle(.borderless)
                    .help(Text(.capsulesBack))
                    .accessibilityLabel(Text(.capsulesBack))
            }
            CapsuleGlyph(size: 17, elevated: false)
            pageTitle.font(.headline).lineLimit(1)
            Spacer(minLength: 8)
            if state.page == .collection {
                Button(.capsulesNew, systemImage: "plus") { state.beginNewCapsule() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var pageTitle: Text {
        switch state.page {
        case .collection: Text(.capsulesName)
        case .selection: Text(.capsulesChooseWindows)
        case .draft: Text(.capsulesReviewDraft)
        case .detail: state.detail.map { Text(verbatim: $0.title) } ?? Text(.capsulesDetails)
        }
    }

    @ViewBuilder private var content: some View {
        switch state.page {
        case .collection: collection
        case .selection: selection
        case .draft: draft
        case .detail: detail
        }
    }

    private var collection: some View {
        Group {
            if state.capsules.isEmpty {
                ContentUnavailableView {
                    Label { Text(.capsulesEmptyTitle) } icon: { CapsuleGlyph(size: 34) }
                } description: {
                    Text(.capsulesEmptyMessage)
                } actions: {
                    Button(.capsulesNew) { state.beginNewCapsule() }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(state.capsules) { capsule in
                            Button { state.show(capsule) } label: {
                                SessionCapsuleRow(capsule: capsule)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    state.resumeCapsule?(capsule)
                                } label: {
                                    Label(.capsulesResume, systemImage: "play.fill")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    state.deleteCapsule?(capsule.id)
                                } label: {
                                    Label(.capsulesDelete, systemImage: "trash")
                                }
                            }
                            .accessibilityAction(named: Text(.capsulesResume)) {
                                state.resumeCapsule?(capsule)
                            }
                            .accessibilityAction(named: Text(.capsulesDelete)) {
                                state.deleteCapsule?(capsule.id)
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selection: some View {
        VStack(spacing: 0) {
            if state.busy {
                SessionCapsuleProgressView(headline: .capsulesFindingWindows,
                                           symbol: "macwindow.on.rectangle")
            } else if state.permissionRequired {
                ContentUnavailableView {
                    Label(.capsulesScreenRecordingTitle, systemImage: "rectangle.dashed.badge.record")
                } description: {
                    Text(.capsulesScreenRecordingMessage)
                } actions: {
                    Button(.capsulesAllowScreenRecording) { state.requestPermission?() }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(state.candidates) { candidate in
                            WindowChoiceRow(candidate: candidate,
                                selected: state.selectedWindowIDs.contains(candidate.id)) {
                                if state.selectedWindowIDs.contains(candidate.id) {
                                    state.selectedWindowIDs.remove(candidate.id)
                                } else if state.selectedWindowIDs.count < SessionCapsuleDocument.maximumWindowsPerCapsule {
                                    state.selectedWindowIDs.insert(candidate.id)
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                Divider()
                HStack {
                    Text(.capsulesSelectedWindows(count: state.selectedWindowIDs.count))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(.capsulesCreateDraft) { state.compose() }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.selectedWindowIDs.isEmpty)
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var draft: some View {
        if state.busy || state.draft == nil {
            SessionCapsuleProgressView(headline: .capsulesReadingContext, symbol: "sparkles")
        } else {
            SessionCapsuleDraftForm(draft: draftBinding) { state.save() }
        }
    }

    /// Only read while `state.draft` is non-nil; the empty draft keeps the binding non-optional.
    private var draftBinding: Binding<SessionCapsuleDraft> {
        Binding(get: {
            state.draft ?? SessionCapsuleDraft(title: "", summary: "", unfinishedTasks: [],
                                               windows: [], note: "")
        }, set: { state.draft = $0 })
    }

    @ViewBuilder private var detail: some View {
        if let capsule = state.detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader(capsule)
                    SessionCapsuleFormSection(.capsulesSummary, symbol: "text.alignleft") {
                        Text(capsule.summary).textSelection(.enabled).capsuleReadingCard()
                    }
                    if !capsule.unfinishedTasks.isEmpty {
                        SessionCapsuleFormSection(.capsulesUnfinished, symbol: "checklist.unchecked") {
                            VStack(spacing: 6) {
                                ForEach(capsule.unfinishedTasks, id: \.self) { task in
                                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                                        Image(systemName: "circle").font(.caption)
                                            .foregroundStyle(.tertiary).accessibilityHidden(true)
                                        Text(task).textSelection(.enabled)
                                        Spacer(minLength: 0)
                                    }
                                    .capsuleReadingCard()
                                }
                            }
                        }
                    }
                    if !capsule.note.isEmpty {
                        SessionCapsuleFormSection(.capsulesNoteHeading, symbol: "bookmark") {
                            Text(capsule.note).textSelection(.enabled).capsuleReadingCard()
                        }
                    }
                    SessionCapsuleWindowList(windows: capsule.windows)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            Divider()
            HStack(spacing: 10) {
                Button(.capsulesDelete, role: .destructive) { state.deleteCapsule?(capsule.id) }
                Spacer(minLength: 12)
                Button(.capsulesResume, systemImage: "play.fill") { state.resumeCapsule?(capsule) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    /// The saved counterpart of the draft's title field: the same weight and rhythm, read-only, with
    /// the capsule's applications shown alongside the timestamp so the checkpoint is placeable at a glance.
    private func detailHeader(_ capsule: SessionCapsule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(capsule.title)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Image(systemName: "clock").font(.caption2).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(capsule.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                TwinedAppIconStack(icons: SessionCapsuleApplicationIcons.icons(for: capsule.windows),
                                   size: 20)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Label { Text(verbatim: message).lineLimit(2) } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        }
        .font(.callout).padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading).background(.quaternary)
    }
}

private struct SessionCapsuleRow: View {
    let capsule: SessionCapsule
    var body: some View {
        HStack(spacing: 10) {
            CapsuleGlyph(size: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(capsule.title).font(.headline).lineLimit(1)
                Text(capsule.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                TwinedAppIconStack(icons: SessionCapsuleApplicationIcons.icons(for: capsule.windows),
                                   size: 17)
                Text(capsule.createdAt, format: .relative(presentation: .named))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(10).contentShape(.rect).background(.quaternary.opacity(0.55), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

private struct WindowChoiceRow: View {
    let candidate: WindowContextCandidate
    let selected: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title ?? String(localized: .capsulesUntitledWindow)).lineLimit(1)
                    Text(candidate.applicationName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8).contentShape(.rect)
            .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Session Capsules") {
    SessionCapsulePanelView(state: SessionCapsulePanelState(capsules: [
        SessionCapsule(title: "Continue DeeDock settings work",
                       summary: "The Features pane and Dock behavior are ready for review.",
                       unfinishedTasks: ["Review the permission fallback"],
                       windows: [.init(applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
                                       windowTitle: "DeeDock")], note: "Check on the external display.")
    ]), forceOpaqueBackground: true)
    .frame(width: 560, height: 500)
}
#endif
