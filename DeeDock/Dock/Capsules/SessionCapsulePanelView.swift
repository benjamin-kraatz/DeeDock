import SwiftUI

/// Deliberate checkpoint flow: choose visible windows, review an editable draft, then save.
///
/// Every page shares one skeleton — header, scrolling body of labelled cards, footer bar holding that
/// page's primary action — so moving through the flow never re-flows the panel. Pages swap without a
/// transition: the header, which is the part that actually changes between them, carries the motion.
struct SessionCapsulePanelView: View {
    let state: SessionCapsulePanelState
    var sourceNavigator: SessionCapsuleSourceNavigator? = nil
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
        case .selection: Text(state.isBreadcrumb ? .breadcrumbLeave : .capsulesChooseWindows)
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
            VStack(spacing: 0) {
                CapsuleEmptyState(
                    title: .capsulesEmptyTitle,
                    message: .capsulesEmptyMessage,
                    action: .capsulesNew,
                    actionSymbol: "plus"
                ) { state.beginNewCapsule() }
                Button(.breadcrumbLeave, systemImage: "bookmark") { state.beginNewCapsule(breadcrumb: true) }
                    .keyboardShortcut("b", modifiers: .command)
                    .padding(.bottom, 16)
            }
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
                    Button(.breadcrumbLeave, systemImage: "bookmark") { state.beginNewCapsule(breadcrumb: true) }
                        .keyboardShortcut("b", modifiers: .command)
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

    private var selection: some View {
        VStack(spacing: 0) {
            selectionContent
            HStack {
                Button(.breadcrumbWriteManually) { state.writeBreadcrumb() }
                    .keyboardShortcut("m", modifiers: .command)
                Spacer()
                Text(.breadcrumbManualHint).font(.caption).foregroundStyle(.secondary)
            }
            .capsuleFooterBar()
        }
    }

    @ViewBuilder private var selectionContent: some View {
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
                    .symbolEffect(.pulse.byLayer, options: .repeat(.continuous), isActive: !reduceMotion)
            }
        } else if state.candidates.isEmpty {
            CapsuleEmptyState(
                title: .capsulesNoWindowsTitle,
                message: .capsulesNoWindows,
                action: .capsulesRetry,
                actionSymbol: "arrow.clockwise"
            ) {
                state.beginNewCapsule(breadcrumb: state.isBreadcrumb)
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
                    Button(state.isBreadcrumb ? .breadcrumbContinue : .capsulesCreateDraft,
                           systemImage: state.isBreadcrumb ? "arrow.forward" : "sparkles") {
                        if state.isBreadcrumb { state.writeBreadcrumb() } else { state.compose() }
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
            ) {
                if state.draft?.breadcrumb != nil { state.cancelCapture() } else { state.back() }
            }
        } else if state.draft?.breadcrumb != nil {
            SessionBreadcrumbEditor(draft: draftBinding,
                canCapture: !state.captureCandidates.isEmpty,
                capture: { state.generateBreadcrumb() }, save: { state.save() })
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

    private var detail: some View {
        Group {
            if let capsule = state.detail {
                SessionCapsuleDetailView(capsule: capsule, state: state, sourceNavigator: sourceNavigator)
            }
        }
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
                Text(capsule.summary.isEmpty ? (capsule.note.isEmpty ? capsule.breadcrumb?.nextStep ?? "" : capsule.note) : capsule.summary).font(.caption).foregroundStyle(.secondary)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .symbolEffect(.bounce, value: reduceMotion ? false : selected)
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
                    title: "Continue DDock settings work",
                    summary:
                        "The Features pane and Dock behavior are ready for review.",
                    unfinishedTasks: ["Review the permission fallback"],
                    windows: [
                        .init(
                            applicationName: "Xcode",
                            bundleIdentifier: "com.apple.dt.Xcode",
                            windowTitle: "DDock"
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
