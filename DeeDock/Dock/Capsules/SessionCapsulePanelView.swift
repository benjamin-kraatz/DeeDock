import SwiftUI

/// Deliberate checkpoint flow: choose visible windows, review an editable draft, then save.
///
/// Every page shares one skeleton — header, scrolling body of labelled cards, footer bar holding that
/// page's primary action — so moving through the flow never re-flows the panel. Pages swap without a
/// transition: the header, which is the part that actually changes between them, carries the motion.
struct SessionCapsulePanelView: View {
    let state: SessionCapsulePanelState
    var forceOpaqueBackground = false
    @Environment(\.accessibilityReduceTransparency) private
        var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: CapsuleMotion { CapsuleMotion(enabled: !reduceMotion) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = state.error {
                CapsuleErrorBanner(message: error) { state.error = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(motion.page, value: state.error)
        .environment(\.capsuleMotion, motion)
        .dockPopoverChrome(
            state.chrome,
            opaque: reduceTransparency || forceOpaqueBackground
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.capsulesName))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            if state.page != .collection {
                Button {
                    state.back()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .buttonStyle(.borderless)
                .help(Text(.capsulesBack))
                .accessibilityLabel(Text(.capsulesBack))
                .keyboardShortcut(.escape, modifiers: [])
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            CapsuleGlyph(size: 18, elevated: false)
            VStack(alignment: .leading, spacing: 1) {
                pageTitle.font(.headline).lineLimit(1)
                if let subtitle {
                    subtitle.font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 8)
            if let step = flowStep {
                CapsuleFlowSteps(current: step)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .animation(motion.page, value: state.page)
    }

    private var pageTitle: Text {
        switch state.page {
        case .collection: Text(.capsulesName)
        case .selection: Text(.capsulesChooseWindows)
        case .draft: Text(.capsulesReviewDraft)
        case .detail:
            state.detail.map { Text(verbatim: $0.title) }
                ?? Text(.capsulesDetails)
        }
    }

    /// A second line only where it says something the page body does not.
    private var subtitle: Text? {
        switch state.page {
        case .collection:
            state.capsules.isEmpty
                ? nil : Text(.capsulesCount(count: state.capsules.count))
        case .detail:
            state.detail.map {
                Text($0.createdAt, format: .relative(presentation: .named))
            }
        case .selection, .draft:
            nil
        }
    }

    /// The creation flow's two steps; `nil` on pages that are not part of it.
    private var flowStep: Int? {
        switch state.page {
        case .selection: 0
        case .draft: 1
        case .collection, .detail: nil
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

    // MARK: - Collection

    @ViewBuilder private var collection: some View {
        if state.capsules.isEmpty {
            CapsuleEmptyState(
                title: .capsulesEmptyTitle,
                message: .capsulesEmptyMessage,
                action: .capsulesNew,
                actionSymbol: "plus"
            ) { state.beginNewCapsule() }
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(state.capsules) { capsule in
                            Button {
                                state.show(capsule)
                            } label: {
                                SessionCapsuleRow(capsule: capsule)
                            }
                            .buttonStyle(CapsuleRowButtonStyle())
                            .transition(
                                .opacity.combined(with: .scale(scale: 0.97))
                            )
                            .contextMenu {
                                Button {
                                    state.resumeCapsule?(capsule)
                                } label: {
                                    Label(
                                        .capsulesResume,
                                        systemImage: "play.fill"
                                    )
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
                    .padding(12)
                    .animation(motion.pop, value: state.capsules.map(\.id))
                }
                HStack(spacing: 10) {
                    Label(.capsulesCollectionHint, systemImage: "hand.tap")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 12)
                    Button(.capsulesNew, systemImage: "plus") {
                        state.beginNewCapsule()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("n", modifiers: .command)
                }
                .capsuleFooterBar()
            }
        }
    }

    // MARK: - Window selection

    @ViewBuilder private var selection: some View {
        if state.busy {
            SessionCapsuleProgressView(
                headline: .capsulesFindingWindows,
                symbol: "macwindow.on.rectangle"
            ) { state.back() }
        } else if state.permissionRequired {
            CapsuleEmptyState(
                title: .capsulesScreenRecordingTitle,
                message: .capsulesScreenRecordingMessage,
                action: .capsulesAllowScreenRecording,
                actionSymbol: "checkmark.shield",
                perform: { state.requestPermission?() }
            ) {
                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.system(size: 40, weight: .light)).foregroundStyle(
                        .tint
                    )
            }
        } else if state.candidates.isEmpty {
            CapsuleEmptyState(
                title: .capsulesNoWindowsTitle,
                message: .capsulesNoWindows,
                action: .capsulesRetry,
                actionSymbol: "arrow.clockwise"
            ) {
                state.beginNewCapsule()
            } mark: {
                Image(systemName: "macwindow.badge.plus")
                    .font(.system(size: 40, weight: .light)).foregroundStyle(
                        .tint
                    )
            }
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    SessionCapsuleFormSection(
                        .capsulesVisibleWindows,
                        symbol: "macwindow"
                    ) {
                        Button(
                            selectionIsFull
                                ? .capsulesSelectNone : .capsulesSelectAll
                        ) { toggleAll() }
                        .buttonStyle(.borderless).controlSize(.small)
                    } content: {
                        VStack(spacing: 6) {
                            ForEach(state.candidates) { candidate in
                                WindowChoiceRow(
                                    candidate: candidate,
                                    selected: state.selectedWindowIDs.contains(
                                        candidate.id
                                    ),
                                    blocked: selectionIsFull
                                ) { toggle(candidate) }
                            }
                        }
                    }
                    .padding(CapsuleMetrics.page)
                }
                HStack(spacing: 10) {
                    Text(
                        .capsulesSelectedWindows(
                            count: state.selectedWindowIDs.count
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    if selectionIsFull {
                        Text(.capsulesSelectionLimit)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .transition(.opacity)
                    }
                    Spacer(minLength: 12)
                    Button(.capsulesCreateDraft, systemImage: "sparkles") {
                        state.compose()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.selectedWindowIDs.isEmpty)
                }
                .animation(motion.pop, value: state.selectedWindowIDs)
                .capsuleFooterBar()
            }
        }
    }

    private var selectionIsFull: Bool {
        state.selectedWindowIDs.count
            >= SessionCapsuleDocument.maximumWindowsPerCapsule
    }

    private func toggle(_ candidate: WindowContextCandidate) {
        if state.selectedWindowIDs.contains(candidate.id) {
            state.selectedWindowIDs.remove(candidate.id)
        } else if !selectionIsFull {
            state.selectedWindowIDs.insert(candidate.id)
        }
    }

    /// One control for both directions: fill up to the capsule limit, or clear the selection.
    private func toggleAll() {
        if selectionIsFull {
            state.selectedWindowIDs = []
        } else {
            let room = SessionCapsuleDocument.maximumWindowsPerCapsule
            state.selectedWindowIDs = Set(
                state.candidates.prefix(room).map(\.id)
            )
        }
    }

    // MARK: - Draft

    @ViewBuilder private var draft: some View {
        if state.busy || state.draft == nil {
            SessionCapsuleProgressView(
                headline: .capsulesReadingContext,
                symbol: "sparkles"
            ) { state.back() }
        } else {
            SessionCapsuleDraftForm(draft: draftBinding) { state.save() }
        }
    }

    /// Only read while `state.draft` is non-nil; the empty draft keeps the binding non-optional.
    private var draftBinding: Binding<SessionCapsuleDraft> {
        Binding(
            get: {
                state.draft
                    ?? SessionCapsuleDraft(
                        title: "",
                        summary: "",
                        unfinishedTasks: [],
                        windows: [],
                        note: ""
                    )
            },
            set: { state.draft = $0 }
        )
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        if let capsule = state.detail {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: CapsuleMetrics.section)
                    {
                        detailHeader(capsule)
                        SessionCapsuleFormSection(
                            .capsulesSummary,
                            symbol: "text.alignleft"
                        ) {
                            Text(capsule.summary).textSelection(.enabled)
                                .capsuleReadingCard()
                        }
                        if !capsule.unfinishedTasks.isEmpty {
                            SessionCapsuleFormSection(
                                .capsulesUnfinished,
                                symbol: "checklist.unchecked"
                            ) {
                                VStack(spacing: 6) {
                                    ForEach(capsule.unfinishedTasks, id: \.self)
                                    { task in
                                        HStack(
                                            alignment: .firstTextBaseline,
                                            spacing: 9
                                        ) {
                                            Image(systemName: "circle").font(
                                                .caption
                                            )
                                            .foregroundStyle(.tertiary)
                                            .accessibilityHidden(true)
                                            Text(task).textSelection(.enabled)
                                            Spacer(minLength: 0)
                                        }
                                        .capsuleReadingCard()
                                    }
                                }
                            }
                        }
                        if !capsule.note.isEmpty {
                            SessionCapsuleFormSection(
                                .capsulesNoteHeading,
                                symbol: "bookmark"
                            ) {
                                Text(capsule.note).textSelection(.enabled)
                                    .capsuleReadingCard()
                            }
                        }
                        SessionCapsuleWindowList(windows: capsule.windows)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(CapsuleMetrics.page)
                }
                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        state.deleteCapsule?(capsule.id)
                    } label: {
                        Label(.capsulesDelete, systemImage: "trash")
                    }
                    .buttonStyle(.glass)
                    
                    Spacer(minLength: 12)
                    Button(.capsulesResume, systemImage: "play.fill") {
                        state.resumeCapsule?(capsule)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
                .capsuleFooterBar()
            }
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
                Image(systemName: "clock").font(.caption2).foregroundStyle(
                    .secondary
                )
                .accessibilityHidden(true)
                Text(
                    capsule.createdAt,
                    format: .dateTime.year().month().day().hour().minute()
                )
                .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                TwinedAppIconStack(
                    icons: SessionCapsuleApplicationIcons.icons(
                        for: capsule.windows
                    ),
                    size: 20
                )
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .capsuleSelectionCard(selected: false, emphasized: true)
    }
}

// MARK: - Rows

private struct SessionCapsuleRow: View {
    let capsule: SessionCapsule
    @Environment(\.capsuleRowHovering) private var hovering
    @Environment(\.capsuleMotion) private var motion

    var body: some View {
        HStack(spacing: 10) {
            // The same stack the capsule wears in the Dock, so a row and its tile are one object.
            SessionCapsuleStack(
                icons: SessionCapsuleApplicationIcons.icons(
                    for: capsule.windows
                ),
                size: 38
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(capsule.title).font(.headline).lineLimit(1)
                Text(capsule.summary).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(capsule.createdAt, format: .relative(presentation: .named))
                .font(.caption2).foregroundStyle(.tertiary)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                .opacity(hovering ? 1 : 0)
                .animation(motion.hover, value: hovering)
                .accessibilityHidden(true)
        }
        .padding(10)
        .contentShape(.rect)
        .capsuleSelectionCard(selected: false, emphasized: true)
        .accessibilityElement(children: .combine)
    }
}

/// One visible window offered for capture, with its real application icon so it is recognisable.
private struct WindowChoiceRow: View {
    let candidate: WindowContextCandidate
    let selected: Bool
    /// The capsule already holds as many windows as it may; unselected rows cannot be added.
    let blocked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        candidate.title
                            ?? String(localized: .capsulesUntitledWindow)
                    ).lineLimit(1)
                    Text(candidate.applicationName).font(.caption)
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(
                        selected
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(.tertiary)
                    )
                    .symbolEffect(.bounce, value: selected)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .contentShape(.rect)
            .capsuleSelectionCard(selected: selected)
            .opacity(blocked && !selected ? 0.45 : 1)
        }
        .buttonStyle(CapsuleRowButtonStyle())
        .disabled(blocked && !selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var icon: some View {
        if let image = SessionCapsuleApplicationIcons.icon(
            for: candidate.bundleIdentifier
        ) {
            Image(nsImage: image).resizable().interpolation(.high)
                .frame(width: 24, height: 24).accessibilityHidden(true)
        } else {
            Image(systemName: "macwindow").foregroundStyle(.secondary)
                .frame(width: 24, height: 24).accessibilityHidden(true)
        }
    }
}

#if DEBUG
    #Preview("Session Capsules") {
        SessionCapsulePanelView(
            state: SessionCapsulePanelState(capsules: [
                SessionCapsule(
                    title: "Continue DeeDock settings work",
                    summary:
                        "The Features pane and Dock behavior are ready for review.",
                    unfinishedTasks: ["Review the permission fallback"],
                    windows: [
                        .init(
                            applicationName: "Xcode",
                            bundleIdentifier: "com.apple.dt.Xcode",
                            windowTitle: "DeeDock"
                        )
                    ],
                    note: "Check on the external display."
                )
            ]),
            forceOpaqueBackground: true
        )
        .frame(width: 560, height: 500)
    }

    #Preview("Session Capsules — Empty") {
        SessionCapsulePanelView(
            state: SessionCapsulePanelState(capsules: []),
            forceOpaqueBackground: true
        )
        .frame(width: 560, height: 500)
    }
#endif
