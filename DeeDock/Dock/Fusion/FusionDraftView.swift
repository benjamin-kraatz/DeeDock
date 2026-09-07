import SwiftUI

/// Step three: the generated artifact, still editable, with the provenance it was frozen with.
struct FusionDraftView: View {
    @Bindable var state: FusionState
    let draft: FusionDraft

    private var locked: Bool { state.savedURL != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: FusionMetrics.section) {
            FusionSection(.fusionReviewResult, symbol: "doc.text") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(.fusionArtifactTitle, text: Binding(
                        get: { state.draft?.title ?? "" },
                        set: { state.draft?.title = String($0.prefix(160)) }))
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 11).padding(.vertical, 9)
                        .fusionCard(emphasized: true)
                        .disabled(locked)
                    TextEditor(text: Binding(
                        get: { state.draft?.body ?? "" },
                        set: { state.draft?.body = String($0.prefix(20_000)) }))
                        .font(.callout)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 8).padding(.vertical, 7)
                        .frame(minHeight: 240)
                        .background(.background.opacity(0.35), in: .rect(cornerRadius: FusionMetrics.cardRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: FusionMetrics.cardRadius)
                                .strokeBorder(.quaternary, lineWidth: 1)
                        }
                        .accessibilityLabel(Text(.fusionArtifactBody))
                        .disabled(locked)
                }
            }
            FusionSection(.fusionSources, symbol: "list.bullet.rectangle") {
                VStack(spacing: 6) {
                    ForEach(Array(draft.sources.enumerated()), id: \.element.id) { index, source in
                        provenanceRow(index: index + 1, source: source)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.caption2).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(.fusionGeneratedOn).font(.caption).foregroundStyle(.secondary)
                Text(draft.generatedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            if locked {
                FusionNotice(.fusionSaved, tone: .success)
            }
        }
        .disabled(state.isBusy)
    }

    private func provenanceRow(index: Int, source: FusionProvenance) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: "\(index)")
                .font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.tertiary)
                .frame(width: 12, alignment: .trailing)
            FusionAppIcon(bundleIdentifier: source.bundleIdentifier, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: source.application).font(.callout.weight(.medium)).lineLimit(1)
                Text(verbatim: source.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                FusionCaptureBadge(state: source.state, edited: source.edited)
                if let date = source.capturedAt {
                    Text(date, format: .dateTime.hour().minute())
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .fusionCard()
        .accessibilityElement(children: .combine)
    }
}
