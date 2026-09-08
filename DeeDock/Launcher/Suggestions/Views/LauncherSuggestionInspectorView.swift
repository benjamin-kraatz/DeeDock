#if DEBUG
import SwiftUI

/// Frozen diagnostics with editable replay tuning. Replays cancel when the sheet closes.
struct LauncherSuggestionInspectorView: View {
    let store: LauncherSuggestionsStore
    var applications: [LauncherApplication] = []
    @Environment(\.dismiss) private var dismiss
    @State private var operation: Operation?
    @State private var selectedTab = Tab.summary
    @State private var selectedEngine = LauncherSuggestionEngine.coreML

    private enum Operation: Equatable {
        case replay(UUID), generate(UUID), step(UUID), run(UUID)
    }

    private enum Tab: Hashable {
        case scenario, summary, candidates, neighbors, history
    }

    private var names: [String: String] {
        Dictionary(applications.map { ($0.id, $0.reference.name) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(.launcherSuggestionsDebugInspectorTitle).font(.title2)
                Spacer()
                Button(.launcherSuggestionsDebugDone) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Picker(selection: Binding(get: { store.debugSource }, set: { source in
                operation = nil
                store.setDebugSource(source)
            })) {
                Text(.launcherSuggestionsSyntheticRealSource).tag(LauncherSuggestionDebugSource.realHistory)
                Text(.launcherSuggestionsSyntheticSource).tag(LauncherSuggestionDebugSource.synthetic)
            } label: {
                Text(.launcherSuggestionsSyntheticSourcePicker)
            }
            .pickerStyle(.segmented)
            HStack {
                if store.debugSource == .realHistory {
                    Button(.launcherSuggestionsDebugCaptureLatest) { store.captureLatestDebugSnapshot() }
                        .disabled(store.debugBusy)
                }
                Button(.launcherSuggestionsDebugReplay) { operation = .replay(UUID()) }
                    .disabled(store.debugBusy || store.debugSnapshot == nil)
                Spacer()
                if store.debugBusy {
                    ProgressView().controlSize(.small)
                    Button(.launcherSuggestionsDebugStop) {
                        operation = nil
                        store.cancelDebugReplay()
                    }
                }
            }
            Text(store.debugSource == .synthetic ? .launcherSuggestionsSyntheticIsolation : .launcherSuggestionsDebugInspectorHelp)
                .font(.callout)
                .foregroundStyle(.secondary)
            if store.debugError {
                Label { Text(.launcherSuggestionsDebugReplayError) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .foregroundStyle(.secondary)
            }
            if store.debugSource == .synthetic || store.debugSnapshot != nil {
                TabView(selection: $selectedTab) {
                    if store.debugSource == .synthetic {
                        LauncherSuggestionSyntheticControlsView(store: store,
                            cancelOperation: { operation = nil },
                            generate: { operation = .generate(UUID()) },
                            step: { operation = .step(UUID()) },
                            run: { operation = .run(UUID()) })
                            .tabItem { Text(.launcherSuggestionsSyntheticScenario) }
                            .tag(Tab.scenario)
                    }
                    if let snapshot = store.debugSnapshot {
                        summary(snapshot)
                        .tabItem { Text(.launcherSuggestionsDebugSummary) }
                        .tag(Tab.summary)
                        candidates(snapshot)
                        .tabItem { Text(.launcherSuggestionsDebugCandidates) }
                        .tag(Tab.candidates)
                        neighbors(snapshot)
                        .tabItem { Text(.launcherSuggestionsDebugNeighborTab) }
                        .tag(Tab.neighbors)
                        history(snapshot)
                        .tabItem { Text(.launcherSuggestionsDebugHistory) }
                        .tag(Tab.history)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label { Text(.launcherSuggestionsDebugEmptyTitle) } icon: { Image(systemName: "chart.bar.xaxis") }
                } description: {
                    Text(.launcherSuggestionsDebugEmptyHelp)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 840, idealWidth: 960, minHeight: 580, idealHeight: 700)
        .task(id: operation) {
            switch operation {
            case .replay: await store.replayDebug()
            case .generate: await store.generateSyntheticHistory()
            case .step: await store.stepSyntheticHistory()
            case .run: await store.runSyntheticHistory()
            case nil: break
            }
        }
        .onChange(of: store.debugSource, initial: true) {
            selectedTab = store.debugSource == .synthetic ? .scenario : .summary
        }
        .onChange(of: store.debugSnapshot == nil) {
            if store.debugSnapshot == nil, store.debugSource == .synthetic {
                selectedTab = .scenario
            }
        }
        .onDisappear { store.cancelDebugReplay() }
    }

    private func summary(_ snapshot: LauncherSuggestionDebugSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if snapshot.source == .realHistory {
                    GroupBox {
                    HStack {
                        Text(store.engine == .baseline ? .launcherSuggestionsEngineBaseline : .launcherSuggestionsEngineCoreML)
                        Spacer()
                        if store.engineBusy {
                            Text(.launcherSuggestionsEnginePreparing)
                        } else if store.engineUnavailable {
                            Text(.launcherSuggestionsEngineUnavailable)
                        } else {
                            Text(.launcherSuggestionsDebugIdle)
                        }
                    }
                    .foregroundStyle(.secondary)
                } label: {
                    Text(.launcherSuggestionsDebugLiveEngineTitle)
                }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                    LabeledContent { Text(snapshot.date, format: .dateTime) } label: { Text(.launcherSuggestionsDebugCaptured) }
                    LabeledContent {
                        Text(snapshot.source == .synthetic ? .launcherSuggestionsSyntheticSource : .launcherSuggestionsSyntheticRealSource)
                    } label: { Text(.launcherSuggestionsSyntheticSourcePicker) }
                    if let target = snapshot.expectedTargetID {
                        LabeledContent { Text(verbatim: names[target] ?? target) } label: { Text(.launcherSuggestionsSyntheticRevealedOutcome) }
                    }
                    LabeledContent { Text(snapshot.exampleCount, format: .number) } label: { Text(.launcherSuggestionsDebugHistoryCount) }
                    LabeledContent { Text(snapshot.tuning.minHistory, format: .number) } label: { Text(.launcherSuggestionsDebugMinHistory) }
                    if let first = snapshot.firstExampleDate {
                        LabeledContent { Text(first, format: .dateTime) } label: { Text(.launcherSuggestionsDebugHistoryFirst) }
                    }
                    if let last = snapshot.lastExampleDate {
                        LabeledContent { Text(last, format: .dateTime) } label: { Text(.launcherSuggestionsDebugHistoryLast) }
                    }
                    LabeledContent { Text(snapshot.tuning.neighbors, format: .number) } label: { Text(.launcherSuggestionsDebugNeighbors) }
                    if let evaluation = snapshot.coreML {
                        LabeledContent { Text(evaluation.neighbors.count, format: .number) } label: { Text(.launcherSuggestionsDebugNeighborCount) }
                    }
                    }
                }
                LauncherSuggestionInspectorContext(context: snapshot.context, names: names)
                engineStatus(snapshot.baseline, title: .launcherSuggestionsEngineBaseline)
                engineStatus(snapshot.coreML, title: .launcherSuggestionsEngineCoreML)
                LauncherSuggestionInspectorComparison(baseline: snapshot.baseline, coreML: snapshot.coreML, names: names)
                Text(.launcherSuggestionsDebugCurrentTuningHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LauncherSuggestionDeveloperSettingsView(store: store, showsInspectorButton: false)
            }
            .padding(12)
        }
    }

    private func engineStatus(_ evaluation: LauncherSuggestionEvaluation?, title: LocalizedStringResource) -> some View {
        GroupBox {
            if let evaluation {
                VStack(alignment: .leading, spacing: 6) {
                LabeledContent { Text(evaluation.elapsedMilliseconds, format: .number.precision(.fractionLength(2))) } label: { Text(.launcherSuggestionsDebugElapsed) }
                LabeledContent { Text(evaluation.candidates.filter(\.eligible).count, format: .number) } label: { Text(.launcherSuggestionsDebugEligibleCount) }
                if let preparation = evaluation.preparationMilliseconds {
                    LabeledContent { Text(preparation, format: .number.precision(.fractionLength(2))) } label: { Text(.launcherSuggestionsDebugPreparationTime) }
                }
                if let inference = evaluation.inferenceMilliseconds {
                    LabeledContent { Text(inference, format: .number.precision(.fractionLength(2))) } label: { Text(.launcherSuggestionsDebugInferenceTime) }
                }
                if let reused = evaluation.cacheReused {
                    LabeledContent {
                        Text(reused ? .launcherSuggestionsDebugCacheReused : .launcherSuggestionsDebugCacheRebuilt)
                    } label: { Text(.launcherSuggestionsDebugModelCache) }
                }
                if let neighbors = evaluation.effectiveNeighbors {
                    LabeledContent { Text(neighbors, format: .number) } label: { Text(.launcherSuggestionsDebugEffectiveNeighbors) }
                }
                }
            } else {
                Text(.launcherSuggestionsDebugNotEvaluated).foregroundStyle(.secondary)
            }
        } label: {
            Text(title)
        }
    }

    private func candidates(_ snapshot: LauncherSuggestionDebugSnapshot) -> some View {
        VStack(alignment: .leading) {
            Picker(selection: $selectedEngine) {
                Text(.launcherSuggestionsEngineBaseline).tag(LauncherSuggestionEngine.baseline)
                Text(.launcherSuggestionsEngineCoreML).tag(LauncherSuggestionEngine.coreML)
            } label: { Text(.launcherSuggestionsEnginePicker) }
                .pickerStyle(.segmented)
            if let evaluation = selectedEngine == .baseline ? snapshot.baseline : snapshot.coreML {
                if evaluation.candidates.isEmpty {
                    Text(.launcherSuggestionsDebugNoCandidates).foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(evaluation.candidates, id: \.id) { candidate in
                            LauncherSuggestionInspectorCandidate(candidate: candidate, tuning: snapshot.tuning,
                                                                 historyCount: snapshot.exampleCount,
                                                                 name: names[candidate.id] ?? candidate.id)
                        }
                    }
                }
            } else {
                Text(.launcherSuggestionsDebugNotEvaluated).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
    }

    private func neighbors(_ snapshot: LauncherSuggestionDebugSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text(.launcherSuggestionsDebugNeighborHelp)
                    .foregroundStyle(.secondary)
                if let evaluation = snapshot.coreML {
                    ForEach(evaluation.neighbors, id: \.id) { neighbor in
                        DisclosureGroup {
                            LauncherSuggestionInspectorContext(context: neighbor.context, names: names)
                        } label: {
                            HStack {
                                Text(verbatim: names[neighbor.appID] ?? neighbor.appID)
                                Spacer()
                                Text(neighbor.date, format: .dateTime)
                                Text(neighbor.distance, format: .number.precision(.fractionLength(4)))
                                    .monospacedDigit()
                                    .accessibilityLabel(Text(.launcherSuggestionsDebugDistance))
                            }
                        }
                    }
                } else {
                    Text(.launcherSuggestionsDebugNotEvaluated).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
    }

    private func history(_ snapshot: LauncherSuggestionDebugSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(snapshot.history.reversed(), id: \.id) { example in
                    DisclosureGroup {
                        LauncherSuggestionInspectorContext(context: example.context, names: names)
                    } label: {
                        HStack {
                            Text(verbatim: names[example.context.foregroundID ?? ""] ?? example.context.foregroundID ?? String(localized: .launcherSuggestionsDebugNone))
                            Image(systemName: "arrow.right").accessibilityHidden(true)
                            Text(verbatim: names[example.targetID] ?? example.targetID)
                            Spacer()
                            Text(example.date, format: .dateTime)
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}
#endif
