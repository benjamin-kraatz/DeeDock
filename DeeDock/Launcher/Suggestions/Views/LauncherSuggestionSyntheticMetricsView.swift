#if DEBUG
import SwiftUI

/// Chronological scores distinguish abstention from failed predictions and missed outcomes.
struct LauncherSuggestionSyntheticMetricsView: View {
    let playback: LauncherSuggestionSyntheticPlayback

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text(.launcherSuggestionsDebugMetric)
                        Text(.launcherSuggestionsEngineBaseline)
                        Text(.launcherSuggestionsEngineCoreML)
                    }
                    .font(.caption.weight(.semibold))
                    count(.launcherSuggestionsSyntheticPredictions, \.predictions)
                    count(.launcherSuggestionsSyntheticOffered, \.offered)
                    count(.launcherSuggestionsSyntheticHits, \.hits)
                    count(.launcherSuggestionsSyntheticFailures, \.failures)
                    GridRow {
                        Text(.launcherSuggestionsSyntheticCoverage)
                        Text(playback.baseline.coverage, format: .percent.precision(.fractionLength(1)))
                        Text(playback.coreML.coverage, format: .percent.precision(.fractionLength(1)))
                    }
                    GridRow {
                        Text(.launcherSuggestionsSyntheticHitRate)
                        rate(playback.baseline.hitRate)
                        rate(playback.coreML.hitRate)
                    }
                    GridRow {
                        Text(.launcherSuggestionsSyntheticAdaptation)
                        adaptation(playback.baseline.adaptationSteps)
                        adaptation(playback.coreML.adaptationSteps)
                    }
                }
                .monospacedDigit()
                Text(.launcherSuggestionsSyntheticMetricsHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(.launcherSuggestionsSyntheticMetrics)
        }
    }

    private func count(_ title: LocalizedStringResource, _ keyPath: KeyPath<LauncherSuggestionSyntheticMetrics, Int>) -> some View {
        GridRow {
            Text(title)
            Text(playback.baseline[keyPath: keyPath], format: .number)
            Text(playback.coreML[keyPath: keyPath], format: .number)
        }
    }

    @ViewBuilder private func rate(_ value: Double?) -> some View {
        if let value {
            Text(value, format: .percent.precision(.fractionLength(1)))
        } else {
            Text(.launcherSuggestionsSyntheticNoRate).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func adaptation(_ value: Int?) -> some View {
        if let value {
            Text(value, format: .number)
        } else {
            Text(.launcherSuggestionsSyntheticNoAdaptation).foregroundStyle(.secondary)
        }
    }
}
#endif
