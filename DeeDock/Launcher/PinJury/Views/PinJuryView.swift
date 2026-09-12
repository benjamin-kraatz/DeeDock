import SwiftUI

/// A native debate room for a single display's pin-succession recommendation.
/// Opening the view never starts generation or applies a pin change.
struct PinJuryView: View {
    let state: PinJuryState
    let openHistorySettings: () -> Void
    @State private var followsConversation = true

    private let transcriptEnd = "pin-jury-transcript-end"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let juryCase = state.currentCase {
                            candidates(juryCase)
                        }
                        PinJuryRoster(activeJuror: state.isBusy ? state.turns.last?.juror : nil)
                        if let message = state.message {
                            PinJuryStatusNotice(message: message, needsHistory: state.needsHistory)
                        }
                        conversation
                        Color.clear.frame(height: 1).id(transcriptEnd)
                            .accessibilityHidden(true)
                    }
                    .padding(24)
                }
                .onChange(of: state.turns.last?.text) { _, _ in
                    // Users can turn off following to read earlier arguments. No animated
                    // scroll is used, including when Reduce Motion is enabled.
                    if followsConversation, state.isBusy {
                        reader.scrollTo(transcriptEnd, anchor: .bottom)
                    }
                }
                .onChange(of: followsConversation) { _, follows in
                    if follows { reader.scrollTo(transcriptEnd, anchor: .bottom) }
                }
            }
            PinJuryDecisionBar(state: state, openHistorySettings: openHistorySettings)
        }
        .background(PinJuryStyle.canvas)
        .frame(minWidth: 760, idealWidth: 940, minHeight: 600, idealHeight: 760)
        .onDisappear {
            if state.isBusy { state.cancel() }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                title
                Spacer(minLength: 8)
                privacyBadge
            }
            VStack(alignment: .leading, spacing: 14) {
                title
                privacyBadge
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    private var title: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 52, height: 52)
                .background(PinJuryStyle.card, in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16).strokeBorder(PinJuryStyle.border)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(.pinJuryTitle).font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(.pinJurySubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var privacyBadge: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Label {
                Text(.pinJuryOnDevice)
            } icon: {
                Image(systemName: "apple.intelligence")
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(PinJuryStyle.card, in: .capsule)
            Text(verbatim: state.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private func candidates(_ juryCase: PinJuryCase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(.pinJuryOnePlace).font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(.pinJuryEvidenceWindow)
                    .font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    PinJuryCandidateCard(candidate: juryCase.incumbent, isIncumbent: true)
                        .frame(minWidth: 290)
                    PinJuryCandidateCard(candidate: juryCase.challenger, isIncumbent: false)
                        .frame(minWidth: 290)
                }
                VStack(spacing: 12) {
                    PinJuryCandidateCard(candidate: juryCase.incumbent, isIncumbent: true)
                    PinJuryCandidateCard(candidate: juryCase.challenger, isIncumbent: false)
                }
            }
        }
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(.pinJuryConversation).font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !state.turns.isEmpty {
                    Toggle(isOn: $followsConversation) {
                        Text(.pinJuryFollowConversation)
                    }
                    .toggleStyle(.checkbox)
                    .font(.caption)
                }
            }
            if state.turns.isEmpty {
                PinJuryConversationPlaceholder(hasCase: state.currentCase != nil, isBusy: state.isBusy)
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(state.turns) { turn in
                        PinJurySpeechCard(turn: turn)
                    }
                }
            }
        }
    }
}

private struct PinJuryStatusNotice: View {
    let message: LocalizedStringResource
    let needsHistory: Bool

    var body: some View {
        Label {
            Text(message).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: needsHistory ? "chart.bar.xaxis" : "info.circle")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PinJuryStyle.card, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct PinJuryConversationPlaceholder: View {
    let hasCase: Bool
    let isBusy: Bool

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: isBusy ? "sparkles" : "bubble.left.and.bubble.right")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(isBusy ? .pinJuryPreparingTitle : .pinJuryConversationEmptyTitle)
                .font(.title3.weight(.semibold))
            Text(hasCase ? .pinJuryConversationEmptyDetail : .pinJuryNoCaseDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(PinJuryStyle.card, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(PinJuryStyle.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Pin Jury, recommendation") {
    PinJuryView(state: .preview(), openHistorySettings: {})
        .frame(width: 940, height: 760)
}

#Preview("Pin Jury, German, dark, live") {
    PinJuryView(state: .preview(phase: .generating), openHistorySettings: {})
        .frame(width: 760, height: 640)
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}

#Preview("Pin Jury, no history") {
    PinJuryView(state: .preview(phase: .unavailable), openHistorySettings: {})
        .frame(width: 860, height: 680)
}
#endif
