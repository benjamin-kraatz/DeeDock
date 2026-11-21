import Foundation
import FoundationModels
import Observation

/// Keeps `FlixIntelligence.engines` current while Flix Files runs, without polling.
///
/// It reads ``FlixEngineStatus/current(lookout:robi:)`` once and then again whenever something it
/// depends on changes, through Observation: Lookout's settings and running state
/// (`LookoutEngine` is `@Observable`; its fast-changing index progress is not read), the system
/// model's availability (`SystemLanguageModel` is `Observable`), and Robi's chosen model and key
/// (`RobiStore`). Each change re-arms the next observation from a main-actor task; ``stop()`` bumps
/// the generation so the chain ends. Main actor.
@MainActor
final class FlixEngineMonitor {
    private let intelligence: FlixIntelligence
    private let lookout: LookoutEngine?
    private let robi: RobiStore?
    private var generation = 0

    init(intelligence: FlixIntelligence, lookout: LookoutEngine?, robi: RobiStore?) {
        self.intelligence = intelligence
        self.lookout = lookout
        self.robi = robi
    }

    func start() {
        generation += 1
        track(generation: generation)
    }

    func stop() { generation += 1 }

    private func track(generation: Int) {
        guard generation == self.generation else { return }
        let status = withObservationTracking {
            _ = lookout?.isRunning
            _ = lookout?.status
            _ = robi?.settings.answerModel
            _ = robi?.hasClaudeKey
            return FlixEngineStatus.current(lookout: lookout?.settings, robi: robi)
        } onChange: { [weak self] in
            Task { @MainActor [self] in self?.track(generation: generation) }
        }
        if intelligence.engines != status { intelligence.engines = status }
    }
}
