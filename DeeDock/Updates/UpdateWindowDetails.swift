#if DIRECT_DISTRIBUTION
import SwiftUI

/// Native release notes, progress and recovery details; no Sparkle view or remote styling is used.
struct UpdateWindowDetails: View {
    let presentation: UpdatePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let offer = presentation.offer,
               [.available, .downloading, .extracting, .ready].contains(presentation.phase) {
                LabeledContent {
                    Text(verbatim: offer.version).monospacedDigit()
                } label: { Text(.updatesVersion) }
                .font(.subheadline)
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                if offer.critical {
                    Label { Text(.updatesCritical) } icon: { Image(systemName: "exclamationmark.shield") }
                        .foregroundStyle(.orange)
                } else if offer.major {
                    Text(.updatesMajorUpgrade).font(.callout).foregroundStyle(.secondary)
                }
            }

            if [.checking, .downloading, .extracting, .installing].contains(presentation.phase) {
                UpdateProgressView(presentation: presentation)
            }

            if presentation.phase == .available {
                VStack(alignment: .leading, spacing: 12) {
                    Text(.updatesReleaseNotes).font(.headline).accessibilityAddTraits(.isHeader)
                    if let notes = presentation.notes {
                        UpdateReleaseNotesView(blocks: notes)
                    } else if presentation.loadingNotes {
                        ProgressView { Text(.updatesLoadingNotes) }.controlSize(.small)
                    } else {
                        Text(presentation.notesUnavailable ? .updatesNotesFailed : .updatesNoNotes)
                            .foregroundStyle(.secondary)
                    }
                    if let url = presentation.offer?.releaseNotesURL {
                        Link(.updatesReadReleaseNotes, destination: url)
                    }
                }
            }

            if presentation.phase == .permission {
                Label { Text(.updatesPermissionPrivacy) } icon: { Image(systemName: "hand.raised") }
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let diagnostic = presentation.diagnostic {
                DisclosureGroup {
                    Text(verbatim: diagnostic)
                        .font(.callout).textSelection(.enabled)
                        .padding(.top, 8)
                } label: { Text(.updatesErrorDetails) }
            }
        }
    }
}

private struct UpdateProgressView: View {
    let presentation: UpdatePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let progress = presentation.progress {
                ProgressView(value: progress)
                    .accessibilityLabel(Text(presentation.title))
            } else {
                ProgressView().progressViewStyle(.linear)
                    .accessibilityLabel(Text(presentation.title))
            }
            if presentation.phase == .downloading {
                HStack {
                    Text(.updatesDownloadedAmount)
                    Spacer()
                    Text(Int64(clamping: presentation.receivedBytes), format: .byteCount(style: .file))
                        .monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 8)
    }
}
#endif
