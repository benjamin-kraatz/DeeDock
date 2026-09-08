#if DEBUG
import SwiftUI

/// Draft scenario settings and deliberate, cancellable operations on isolated generated history.
struct LauncherSuggestionSyntheticControlsView: View {
    let store: LauncherSuggestionsStore
    let cancelOperation: () -> Void
    let generate: () -> Void
    let step: () -> Void
    let run: () -> Void

    private func binding<Value>(_ keyPath: WritableKeyPath<LauncherSuggestionSyntheticConfiguration, Value>) -> Binding<Value> {
        Binding(get: { store.syntheticConfiguration[keyPath: keyPath] }, set: { value in
            cancelOperation()
            var configuration = store.syntheticConfiguration
            configuration[keyPath: keyPath] = value
            store.setSyntheticConfiguration(configuration)
        })
    }

    private var scenario: Binding<LauncherSuggestionSyntheticScenario> {
        Binding(get: { store.syntheticConfiguration.scenario }, set: { scenario in
            cancelOperation()
            var configuration = store.syntheticConfiguration
            configuration.scenario = scenario
            configuration.exampleCount = scenario == .coldStart ? 5 : 120
            configuration.days = scenario == .burst ? 1 : 14
            store.setSyntheticConfiguration(configuration)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
                SettingsCard(title: .launcherSuggestionsSyntheticGenerator,
                             footnote: .launcherSuggestionsSyntheticDraftHelp) {
                    SettingsMenuRow(title: .launcherSuggestionsSyntheticScenario, selection: scenario) {
                        ForEach(LauncherSuggestionSyntheticScenario.allCases, id: \.self) { scenario in
                            Text(title(scenario)).tag(scenario)
                        }
                    }
                    integerRow(.launcherSuggestionsSyntheticExampleCount, selection: binding(\.exampleCount), range: 0...1_000)
                    integerRow(.launcherSuggestionsSyntheticDays, selection: binding(\.days), range: 1...90)
                        .disabled(store.syntheticConfiguration.scenario == .burst)
                    proportionRow(.launcherSuggestionsSyntheticPatternStrength, selection: binding(\.patternStrength))
                    proportionRow(.launcherSuggestionsSyntheticNoise, selection: binding(\.noise))
                    SettingsRow(title: .launcherSuggestionsSyntheticSeed) {
                        TextField(value: binding(\.seed), format: .number.grouping(.never)) {
                            Text(.launcherSuggestionsSyntheticSeed)
                        }
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    }
                    SettingsRow(title: .launcherSuggestionsSyntheticReferenceDate) {
                        DatePicker(selection: binding(\.referenceDate), displayedComponents: [.date, .hourAndMinute]) {
                            Text(.launcherSuggestionsSyntheticReferenceDate)
                        }
                        .labelsHidden()
                        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                    }
                    SettingsActionRow {
                        Button(.launcherSuggestionsSyntheticGenerate, action: generate)
                            .disabled(store.debugBusy)
                    }
                }
                if let playback = store.syntheticPlayback {
                    SettingsCard(title: .launcherSuggestionsSyntheticPlayback,
                                 footnote: .launcherSuggestionsSyntheticPlaybackHelp) {
                        SettingsStackedRow {
                            HStack {
                                Text(.launcherSuggestionsSyntheticProgress)
                                Spacer()
                                Text(playback.position, format: .number)
                                Text(verbatim: "/")
                                Text(playback.total, format: .number)
                            }
                            ProgressView(value: Double(playback.position), total: Double(max(1, playback.total))) {
                                Text(.launcherSuggestionsSyntheticProgress)
                            }
                            .labelsHidden()
                        }
                        SettingsActionRow {
                            Button(.launcherSuggestionsSyntheticRestart) { store.resetSyntheticPlayback() }
                                .disabled(store.debugBusy)
                            Button(.launcherSuggestionsSyntheticStep, action: step)
                                .disabled(store.debugBusy || playback.position >= playback.total)
                            Button(.launcherSuggestionsSyntheticRun, action: run)
                                .disabled(store.debugBusy || playback.position >= playback.total)
                        }
                    }
                    LauncherSuggestionSyntheticMetricsView(playback: playback)
                }
                if store.debugSnapshot != nil {
                    SettingsCard(title: .launcherSuggestionsSyntheticClock,
                                 footnote: .launcherSuggestionsSyntheticClockHelp) {
                        if let snapshot = store.debugSnapshot {
                            SettingsRow(title: .launcherSuggestionsSyntheticEvaluationDate) {
                                Text(snapshot.date, format: .dateTime)
                                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                            }
                        }
                        SettingsActionRow {
                            Button(.launcherSuggestionsSyntheticAdvanceOne) { store.advanceSyntheticDays(1) }
                            Button(.launcherSuggestionsSyntheticAdvanceSeven) { store.advanceSyntheticDays(7) }
                            Button(.launcherSuggestionsSyntheticAdvanceThirty) { store.advanceSyntheticDays(30) }
                        }
                        .disabled(store.debugBusy)
                    }
                }
            }
            .padding(12)
        }
    }

    private func integerRow(_ title: LocalizedStringResource, selection: Binding<Int>, range: ClosedRange<Int>) -> some View {
        SettingsRow(title: title) {
            Stepper(value: selection, in: range) {
                Text(selection.wrappedValue, format: .number).monospacedDigit()
            }
            .fixedSize()
            .accessibilityLabel(Text(title))
        }
    }

    private func proportionRow(_ title: LocalizedStringResource, selection: Binding<Double>) -> some View {
        SettingsStackedRow {
            HStack {
                Text(title)
                Spacer()
                Text(selection.wrappedValue, format: .percent.precision(.fractionLength(0))).monospacedDigit()
            }
            Slider(value: selection, in: 0...1, step: 0.05) { Text(title) }
        }
    }

    private func title(_ scenario: LauncherSuggestionSyntheticScenario) -> LocalizedStringResource {
        switch scenario {
        case .coldStart: .launcherSuggestionsSyntheticColdStart
        case .routine: .launcherSuggestionsSyntheticRoutine
        case .burst: .launcherSuggestionsSyntheticBurst
        case .conflicting: .launcherSuggestionsSyntheticConflicting
        case .drift: .launcherSuggestionsSyntheticDrift
        case .unfamiliar: .launcherSuggestionsSyntheticUnfamiliar
        }
    }
}
#endif
