import SwiftUI

/// Everything the update panel shows under its header: offer flags, progress, the What’s
/// New comic, release notes, the idle-install switch, and recovery details.
///
/// Native views only; no Sparkle view or remote styling is used. Sections sit directly on
/// the island's glass. Only the idle-install switch gets an inset card, because it is the
/// one control in a column of reading text.
struct UpdatePanelDetails: View {
    let presentation: UpdatePresentation
    var awareness: UpdateAwarenessStore? = nil

    private var offerIsCurrent: Bool {
        [.available, .downloading, .extracting, .ready].contains(presentation.phase)
    }

    /// The notes section also explains a missing or failed download, so it stays whenever
    /// there is no comic to stand in for it.
    private var showsNotesSection: Bool {
        presentation.notes != nil || presentation.loadingNotes || presentation.notesUnavailable
            || presentation.offer?.releaseNotesURL != nil || presentation.comic == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let offer = presentation.offer, offerIsCurrent {
                if offer.critical {
                    Label { Text(.updatesCritical) } icon: { Image(systemName: "exclamationmark.shield.fill") }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.orange)
                } else if offer.major {
                    Text(.updatesMajorUpgrade).font(.callout).foregroundStyle(.secondary)
                }
            }

            if [.checking, .downloading, .extracting, .installing].contains(presentation.phase) {
                UpdatePanelProgress(presentation: presentation)
            }

            if presentation.showsNotes {
                if let comic = presentation.comic {
                    UpdatePanelSection(title: .updatesWhatsNew) {
                        UpdateComicView(comic: comic)
                    }
                }
                if showsNotesSection {
                    UpdatePanelSection(title: .updatesReleaseNotes) {
                        if let notes = presentation.notes {
                            UpdateReleaseNotesView(blocks: notes)
                        } else if presentation.loadingNotes {
                            // Centred with room around it, so the placeholder reads as the
                            // section's content and the island grows less when notes arrive.
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(.updatesLoadingNotes).font(.callout).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .accessibilityElement(children: .combine)
                        } else if presentation.notesUnavailable {
                            Text(.updatesNotesFailed).font(.callout).foregroundStyle(.secondary)
                        } else if presentation.comic == nil {
                            Text(.updatesNoNotes).font(.callout).foregroundStyle(.secondary)
                        }
                        if let url = presentation.offer?.releaseNotesURL {
                            Link(.updatesReadReleaseNotes, destination: url).font(.callout)
                        }
                    }
                }
            }

            if presentation.phase == .ready, let awareness {
                UpdateIdleInstallSwitch(awareness: awareness)
            }

            if presentation.phase == .permission {
                Label { Text(.updatesPermissionPrivacy) } icon: { Image(systemName: "hand.raised") }
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let diagnostic = presentation.diagnostic {
                DisclosureGroup {
                    Text(verbatim: diagnostic)
                        .font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                } label: { Text(.updatesErrorDetails).font(.callout) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A quiet caption heading over one block of panel content.
private struct UpdatePanelSection<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The offer's version as a small capsule beside the panel title.
struct UpdateVersionBadge: View {
    let version: String

    var body: some View {
        Text(verbatim: version)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.16), in: .capsule)
            .contentTransition(.numericText())
            .accessibilityElement()
            .accessibilityLabel(Text(.updatesVersion))
            .accessibilityValue(Text(verbatim: version))
    }
}

/// Download, extraction, and install progress in the update gradient.
///
/// A known fraction draws a static bar that only moves when the value does. An unknown one
/// uses the system's indeterminate bar, which animates for as long as that phase lasts.
private struct UpdatePanelProgress: View {
    let presentation: UpdatePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress = presentation.progress {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule()
                                .fill(UpdateAwarenessMark.fill)
                                .frame(width: max(6, geometry.size.width * progress))
                        }
                    }
                    .animation(.smooth(duration: 0.3), value: progress)
                    .accessibilityElement()
                    .accessibilityLabel(Text(presentation.title))
                    .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
            } else {
                ProgressView().progressViewStyle(.linear)
                    .controlSize(.small)
                    .accessibilityLabel(Text(presentation.title))
            }
            if presentation.phase == .downloading {
                HStack(spacing: 4) {
                    Text(.updatesDownloadedAmount)
                    Spacer()
                    Text(Int64(clamping: presentation.receivedBytes), format: .byteCount(style: .file))
                    if presentation.progress != nil {
                        Text(verbatim: "/")
                        Text(Int64(clamping: presentation.expectedBytes), format: .byteCount(style: .file))
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Ready-to-install opt-in. The same preference lives in Settings. Not shown during onboarding.
struct UpdateIdleInstallSwitch: View {
    let awareness: UpdateAwarenessStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The toggle keeps its label for VoiceOver; the visible copy is laid out
            // separately so the switch sits at the trailing edge.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(.updatesIdleInstallAlso)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
                Toggle(isOn: Binding(
                    get: { awareness.installWhenIdle },
                    set: { awareness.setInstallWhenIdle($0) }
                )) {
                    Text(.updatesIdleInstallAlso)
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            Text(.updatesIdleInstallFootnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Concentric with the island: its 36 pt corner minus the 14 pt content inset.
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

#if DEBUG
#Preview("Idle install switch") {
    UpdateIdleInstallSwitch(awareness: .previewStore())
        .padding()
        .frame(width: 480)
}

#Preview("Idle install switch, German") {
    UpdateIdleInstallSwitch(awareness: .previewStore(idleInstall: true))
        .environment(\.locale, Locale(identifier: "de"))
        .padding()
        .frame(width: 480)
}
#endif

#Preview("Details, downloading") {
    let model = UpdatePresentation(currentVersion: "0.5.0")
    model.phase = .downloading
    model.receivedBytes = 18_000_000
    model.expectedBytes = 42_000_000
    model.offer = UpdateOffer(version: "0.6.0", stage: .notDownloaded, critical: true, major: false,
                              informational: false, informationURL: nil, releaseNotesURL: nil)
    return UpdatePanelDetails(presentation: model).padding().frame(width: 532)
}

#Preview("Details, notes") {
    let model = UpdatePresentation(currentVersion: "0.5.0")
    model.phase = .available
    model.offer = UpdateOffer(version: "0.6.0", stage: .notDownloaded, critical: false, major: true,
                              informational: false, informationURL: nil, releaseNotesURL: nil)
    model.notes = [
        UpdateReleaseNoteBlock(id: 0, style: .heading(2), text: AttributedString("A quieter dock.")),
        UpdateReleaseNoteBlock(id: 1, text: AttributedString("Improved display placement across multiple monitors."), marker: "•"),
        UpdateReleaseNoteBlock(id: 2, text: AttributedString("More precise activation zones"), marker: "•")
    ]
    return UpdatePanelDetails(presentation: model).padding().frame(width: 532)
}
