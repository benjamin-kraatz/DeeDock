import SwiftUI

/// Saved recap with independent personal writing, model interpretation, and explicit source actions.
struct SessionCapsuleDetailView: View {
    let capsule: SessionCapsule
    let state: SessionCapsulePanelState
    var sourceNavigator: SessionCapsuleSourceNavigator?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: CapsuleMetrics.section)
                {
                    detailHeader(capsule)
                    if !capsule.note.isEmpty {
                        SessionCapsuleFormSection(
                            capsule.breadcrumb != nil ? .breadcrumbYourNote : .capsulesNoteHeading,
                            symbol: "bookmark"
                        ) {
                            Text(capsule.note).textSelection(.enabled)
                                .capsuleReadingCard()
                        }
                    }
                    if let breadcrumb = capsule.breadcrumb, !breadcrumb.nextStep.isEmpty {
                        SessionCapsuleFormSection(.breadcrumbNextStep, symbol: "arrow.forward.circle") {
                            Text(verbatim: breadcrumb.nextStep).textSelection(.enabled).capsuleReadingCard()
                        }
                    }
                    if !capsule.summary.isEmpty {
                        SessionCapsuleFormSection(
                            capsule.breadcrumb?.generatedAt != nil ? .breadcrumbInterpretation : .capsulesSummary,
                            symbol: "text.alignleft"
                        ) {
                            if let generatedAt = capsule.breadcrumb?.generatedAt {
                                Text(generatedAt, format: .dateTime.year().month().day().hour().minute()).font(.caption)
                            }
                            Text(capsule.summary).textSelection(.enabled).capsuleReadingCard()
                        }
                    }
                    if !capsule.unfinishedTasks.isEmpty {
                        SessionCapsuleFormSection(
                            capsule.breadcrumb != nil ? .breadcrumbSuggestedSteps : .capsulesUnfinished,
                            symbol: "checklist.unchecked"
                        ) {
                            VStack(spacing: 6) {
                                ForEach(Array(capsule.unfinishedTasks.enumerated()), id: \.offset)
                                { _, task in
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
                    if let sourceNavigator {
                        Text(.breadcrumbRestoreLimits).font(.caption).foregroundStyle(.secondary)
                        Button(.breadcrumbRefreshSources) { sourceNavigator.refresh(capsule.windows) }
                        ForEach(capsule.windows) { reference in
                            SessionBreadcrumbSourceView(reference: reference, navigator: sourceNavigator)
                        }
                    } else {
                        SessionCapsuleWindowList(windows: capsule.windows)
                    }
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
                .tint(.red)
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Button(.breadcrumbEdit) { state.edit(capsule) }
                    .keyboardShortcut("e", modifiers: .command)
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
        .task(id: capsule.id) { sourceNavigator?.refresh(capsule.windows) }
        .onDisappear { sourceNavigator?.cancel() }
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
