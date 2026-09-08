#if DEBUG
import SwiftUI

/// Captured inputs are displayed separately from the outcome that became the training label.
struct LauncherSuggestionInspectorContext: View {
    let context: LauncherSuggestionContext
    let names: [String: String]

    private func appName(_ id: String?) -> String {
        guard let id else { return String(localized: .launcherSuggestionsDebugNone) }
        return names[id] ?? id
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent { Text(context.date, format: .dateTime) } label: { Text(.launcherSuggestionsDebugCaptured) }
                LabeledContent { Text(verbatim: appName(context.foregroundID)) } label: { Text(.launcherSuggestionsDebugForeground) }
                LabeledContent { Text(verbatim: context.modeID ?? String(localized: .launcherSuggestionsDebugNone)) } label: { Text(.launcherSuggestionsDebugMode) }
                LabeledContent { Text(context.hour, format: .number) } label: { Text(.launcherSuggestionsDebugHour) }
                LabeledContent { Text(context.weekday, format: .number) } label: { Text(.launcherSuggestionsDebugWeekday) }
                if let seconds = context.foregroundSeconds {
                    LabeledContent { Text(seconds, format: .number.precision(.fractionLength(2))) } label: { Text(.launcherSuggestionsDebugForegroundSeconds) }
                }
                LabeledContent { Text(verbatim: context.recentIDs.map { appName($0) }.joined(separator: ", ")) } label: { Text(.launcherSuggestionsDebugRecent) }
                LabeledContent { Text(verbatim: context.runningIDs.map { appName($0) }.joined(separator: ", ")) } label: { Text(.launcherSuggestionsDebugRunning) }
            }
            .textSelection(.enabled)
        } label: {
            Text(.launcherSuggestionsDebugContext)
        }
    }
}

/// Shows every score adjustment and the exact evidence thresholds for one candidate.
struct LauncherSuggestionInspectorCandidate: View {
    let candidate: LauncherSuggestionCandidateEvidence
    let tuning: LauncherSuggestionTuning
    let historyCount: Int
    let name: String

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: candidate.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                ForEach(candidate.reasons, id: \.rawValue) { reason in
                    Label { Text(title(reason)) } icon: { Image(systemName: "exclamationmark.circle") }
                }
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    GridRow {
                        Text(.launcherSuggestionsDebugMetric)
                        Text(.launcherSuggestionsDebugValue)
                        Text(.launcherSuggestionsDebugThreshold)
                    }
                    .font(.caption.weight(.semibold))
                    threshold(.launcherSuggestionsDebugHistoryCount, value: Double(historyCount), limit: Double(tuning.minHistory))
                    threshold(.launcherSuggestionsDebugSupport, value: Double(candidate.support), limit: Double(tuning.minSupport))
                    threshold(.launcherSuggestionsDebugDays, value: Double(candidate.distinctDays), limit: Double(tuning.minDays))
                    threshold(.launcherSuggestionsDebugAgreement, value: candidate.agreement, limit: tuning.minAgreement)
                    if let distance = candidate.nearestDistance {
                        threshold(.launcherSuggestionsDebugDistance, value: distance, limit: tuning.maxDistance, maximum: true)
                    }
                }
                Divider()
                metric(.launcherSuggestionsDebugRawScore, candidate.rawScore)
                metric(.launcherSuggestionsDebugAgeFactor, candidate.ageFactor)
                metric(.launcherSuggestionsDebugNormalizedScore, candidate.normalizedScore)
                metric(.launcherSuggestionsDebugRecencyBonus, candidate.recencyBonus)
                metric(.launcherSuggestionsDebugRunningBonus, candidate.runningBonus)
                metric(.launcherSuggestionsDebugFeedbackAdjustment, candidate.feedbackAdjustment)
                metric(.launcherSuggestionsDebugFinalScore, candidate.finalScore)
            }
            .padding(.vertical, 8)
        } label: {
            HStack {
                Text(verbatim: name)
                Spacer()
                Text(candidate.finalScore, format: .number.precision(.fractionLength(4))).monospacedDigit()
                Label {
                    Text(candidate.eligible ? .launcherSuggestionsDebugEligible : .launcherSuggestionsDebugRejected)
                } icon: {
                    Image(systemName: candidate.eligible ? "checkmark.circle" : "minus.circle")
                }
                .foregroundStyle(candidate.eligible ? Color.primary : Color.secondary)
            }
        }
        .padding(10)
        .background(.background.secondary, in: .rect(cornerRadius: 6))
    }

    private func metric(_ title: LocalizedStringResource, _ value: Double) -> some View {
        LabeledContent {
            Text(value, format: .number.precision(.fractionLength(4))).monospacedDigit()
        } label: {
            Text(title)
        }
    }

    private func threshold(_ title: LocalizedStringResource, value: Double, limit: Double, maximum: Bool = false) -> some View {
        GridRow {
            Text(title)
            Text(value, format: .number.precision(.fractionLength(0...4))).monospacedDigit()
            HStack(spacing: 4) {
                Text(verbatim: maximum ? "≤" : "≥")
                Text(limit, format: .number.precision(.fractionLength(0...4))).monospacedDigit()
            }
        }
    }

    private func title(_ reason: LauncherSuggestionGateReason) -> LocalizedStringResource {
        switch reason {
        case .history: .launcherSuggestionsDebugGateHistory
        case .support: .launcherSuggestionsDebugGateSupport
        case .days: .launcherSuggestionsDebugGateDays
        case .agreement: .launcherSuggestionsDebugGateAgreement
        case .distance: .launcherSuggestionsDebugGateDistance
        case .excluded: .launcherSuggestionsDebugGateExcluded
        case .foreground: .launcherSuggestionsDebugGateForeground
        case .nonPositive: .launcherSuggestionsDebugGateNonPositive
        case .unavailable: .launcherSuggestionsDebugGateUnavailable
        }
    }
}
#endif
