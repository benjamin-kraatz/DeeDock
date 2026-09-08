#if DEBUG
import SwiftUI

/// Development-only controls. Model-owned defaults and store mutations keep tuning consistent.
struct LauncherSuggestionDeveloperSettingsView: View {
    let store: LauncherSuggestionsStore
    var showsInspectorButton = true
    var inspect: () -> Void = { }

    private func binding<Value>(_ keyPath: WritableKeyPath<LauncherSuggestionTuning, Value>) -> Binding<Value> {
        Binding(get: { store.tuning[keyPath: keyPath] }, set: { value in
            var tuning = store.tuning
            tuning[keyPath: keyPath] = value
            store.setTuning(tuning)
        })
    }

    var body: some View {
        SettingsCard(title: .launcherSuggestionsDebugTuningTitle,
                     footnote: .launcherSuggestionsDebugTuningHelp) {
            integerRow(.launcherSuggestionsDebugMinHistory, selection: binding(\.minHistory), range: 0...1_000)
            integerRow(.launcherSuggestionsDebugMinSupport, selection: binding(\.minSupport), range: 0...100)
            integerRow(.launcherSuggestionsDebugMinDays, selection: binding(\.minDays), range: 0...30)
            SettingsStackedRow {
                HStack {
                    Text(.launcherSuggestionsDebugMinAgreement)
                    Spacer()
                    Text(store.tuning.minAgreement, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                Slider(value: binding(\.minAgreement), in: 0...1, step: 0.05) {
                    Text(.launcherSuggestionsDebugMinAgreement)
                }
            }
            SettingsStackedRow {
                HStack {
                    Text(.launcherSuggestionsDebugMaxDistance)
                    Spacer()
                    Text(store.tuning.maxDistance, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                }
                Slider(value: binding(\.maxDistance), in: 0...20, step: 0.1) {
                    Text(.launcherSuggestionsDebugMaxDistance)
                }
            }
            integerRow(.launcherSuggestionsDebugNeighbors, selection: binding(\.neighbors), range: 1...100)
            SettingsActionRow {
                Button(.launcherSuggestionsDebugResetTuning) { store.resetTuning() }
                if showsInspectorButton {
                    Button(.launcherSuggestionsDebugInspect, action: inspect)
                }
            }
        }
    }

    private func integerRow(_ title: LocalizedStringResource, selection: Binding<Int>, range: ClosedRange<Int>) -> some View {
        SettingsRow(title: title) {
            Stepper(value: selection, in: range) {
                Text(selection.wrappedValue, format: .number)
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .fixedSize()
            .accessibilityLabel(Text(title))
        }
    }
}
#endif
