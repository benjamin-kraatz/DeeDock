import SwiftUI

/// One streamed turn. Model output remains plain text and cannot create links or UI actions.
struct PinJurySpeechCard: View {
    let turn: PinJuryTurn

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PinJurorAvatar(juror: turn.juror)
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        speaker
                        Spacer(minLength: 6)
                        if let vote = turn.vote { PinJuryVoteBadge(vote: vote) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        speaker
                        if let vote = turn.vote { PinJuryVoteBadge(vote: vote) }
                    }
                }
                if turn.text.isEmpty {
                    Text(.pinJuryConsideringEvidence)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text(verbatim: turn.text)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !turn.isComplete {
                    Label {
                        Text(.pinJurySpeaking)
                    } icon: {
                        Image(systemName: "waveform")
                    }
                    .font(.caption)
                    .foregroundStyle(turn.juror.tint)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PinJuryStyle.card, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(turn.juror.tint.opacity(0.18), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var speaker: some View {
        HStack(spacing: 8) {
            Text(turn.juror.displayName)
                .font(.headline)
                .foregroundStyle(turn.juror.tint)
            Text(.pinJuryRound(turn.round))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
