#if DEBUG
import SwiftUI

/// Aligns each app across engines so abstention and final scores can be compared directly.
struct LauncherSuggestionInspectorComparison: View {
    let baseline: LauncherSuggestionEvaluation?
    let coreML: LauncherSuggestionEvaluation?
    let names: [String: String]

    private struct Row: Identifiable {
        let id: String
        let name: String
        let baseline: LauncherSuggestionCandidateEvidence?
        let coreML: LauncherSuggestionCandidateEvidence?
    }

    private var rows: [Row] {
        let baselineByID = Dictionary((baseline?.candidates ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let coreMLByID = Dictionary((coreML?.candidates ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Set(baselineByID.keys).union(coreMLByID.keys).map { id in
            Row(id: id, name: names[id] ?? id, baseline: baselineByID[id], coreML: coreMLByID[id])
        }.sorted { lhs, rhs in
            let lhsScore = max(lhs.baseline?.finalScore ?? 0, lhs.coreML?.finalScore ?? 0)
            let rhsScore = max(rhs.baseline?.finalScore ?? 0, rhs.coreML?.finalScore ?? 0)
            return lhsScore == rhsScore ? lhs.id < rhs.id : lhsScore > rhsScore
        }
    }

    var body: some View {
        GroupBox {
            if rows.isEmpty {
                Text(.launcherSuggestionsDebugNoCandidates).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Table(rows) {
                    TableColumn(String(localized: .launcherSuggestionsDebugApp)) { row in
                        Text(verbatim: row.name)
                    }
                    TableColumn(String(localized: .launcherSuggestionsEngineBaseline)) { row in
                        score(row.baseline)
                    }
                    TableColumn(String(localized: .launcherSuggestionsEngineCoreML)) { row in
                        score(row.coreML)
                    }
                }
                .frame(height: 240)
            }
        } label: {
            Text(.launcherSuggestionsDebugComparison)
        }
    }

    @ViewBuilder private func score(_ candidate: LauncherSuggestionCandidateEvidence?) -> some View {
        if let candidate {
            HStack(spacing: 8) {
                Text(candidate.finalScore, format: .number.precision(.fractionLength(4)))
                    .monospacedDigit()
                Label {
                    Text(candidate.eligible ? .launcherSuggestionsDebugEligible : .launcherSuggestionsDebugRejected)
                } icon: {
                    Image(systemName: candidate.eligible ? "checkmark.circle" : "minus.circle")
                }
                .font(.caption)
                .foregroundStyle(candidate.eligible ? Color.primary : Color.secondary)
            }
        } else {
            Text(.launcherSuggestionsDebugNoCandidate).foregroundStyle(.secondary)
        }
    }
}
#endif
