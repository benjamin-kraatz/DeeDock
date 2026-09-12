import SwiftUI

/// The only action here that can change pins is an explicit press of Accept.
/// Accept deliberately has no default-action keyboard shortcut.
struct PinJuryDecisionBar: View {
    let state: PinJuryState
    let openHistorySettings: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                summary
                Spacer(minLength: 10)
                actions
            }
            VStack(alignment: .leading, spacing: 14) {
                summary
                HStack { Spacer(); actions }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(PinJuryStyle.card)
        .overlay(alignment: .top) { Divider() }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: summarySymbol)
                .font(.title2)
                .foregroundStyle(state.phase == .accepted ? Color.green : Color.accentColor)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(summaryTitle)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(summaryDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var actions: some View {
        if state.isBusy {
            ProgressView().controlSize(.small)
                .accessibilityLabel(Text(.pinJuryDeliberating))
            Button(.pinJuryCancel) { state.cancel() }
        } else if state.phase == .awaitingDecision {
            Button(.pinJuryReject) { state.reject() }
            Button(.pinJuryAccept) { state.accept() }
                .buttonStyle(.borderedProminent)
                .disabled(!state.canAccept)
                .accessibilityHint(Text(summaryTitle))
        } else if state.needsHistory {
            Button(.pinJuryRefresh) { state.reload() }
            Button(.pinJuryOpenHistorySettings, action: openHistorySettings)
                .buttonStyle(.borderedProminent)
        } else if state.phase == .accepted || state.phase == .rejected {
            Button(.pinJuryNextCase) { state.reload() }
        } else {
            Button(.pinJuryRefresh) { state.reload() }
                .help(Text(.pinJuryRefreshHelp))
            Button(state.turns.isEmpty ? .pinJuryStart : .pinJuryRetry) { state.start() }
                .buttonStyle(.borderedProminent)
                .disabled(!state.canStart)
        }
    }

    private var summarySymbol: String {
        switch state.phase {
        case .accepted: "checkmark.circle.fill"
        case .rejected: "hand.raised.fill"
        case .awaitingDecision: state.finalVote == .replace ? "arrow.triangle.swap" : "pin.fill"
        case .generating: "bubble.left.and.bubble.right"
        case .ready, .unavailable: "hand.point.up.left"
        }
    }

    private var summaryTitle: LocalizedStringResource {
        switch state.phase {
        case .accepted: return .pinJuryDecisionAccepted
        case .rejected: return .pinJuryDecisionRejected
        case .generating: return .pinJuryDeliberating
        case .ready, .unavailable: return .pinJuryYourDecision
        case .awaitingDecision:
            guard let juryCase = state.currentCase, let vote = state.finalVote else {
                return .pinJuryYourDecision
            }
            if vote == .replace {
                return .pinJuryReplaceProposal(juryCase.incumbent.application.name, juryCase.challenger.application.name)
            }
            return .pinJuryKeepProposal(juryCase.incumbent.application.name)
        }
    }

    private var summaryDetail: LocalizedStringResource {
        switch state.phase {
        case .accepted:
            state.finalVote == .replace ? .pinJuryReplacementApplied : .pinJuryKeepApplied
        case .rejected: .pinJuryRejectedDetail
        case .generating: .pinJuryGeneratingDetail
        case .awaitingDecision: .pinJuryAcceptDetail
        case .ready, .unavailable: .pinJuryReadyDetail
        }
    }
}
