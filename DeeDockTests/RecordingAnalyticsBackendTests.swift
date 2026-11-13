import Foundation
import Testing
@testable import DeeDock

/// What Settings › Privacy › "Recently sent" lists for each kind of event.
@MainActor
struct RecordingAnalyticsBackendTests {
    /// Lets the main-actor tasks the backend posts run.
    private func settle(_ log: AnalyticsRecentLog, count: Int) async {
        for _ in 0..<200 where log.records.count < count {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test("An AI generation is listed by name only, without its prompt or answer")
    func aiGenerationIsListedByName() async {
        let log = AnalyticsRecentLog()
        let backend = RecordingAnalyticsBackend(base: NoOpAnalyticsBackend(isConfigured: true), log: log)
        backend.captureAI(AIObservabilityRecord(name: "$ai_generation",
                                                properties: ["$ai_input": "the prompt", "$ai_output_choices": "the answer"]))
        await settle(log, count: 1)
        #expect(log.records.map(\.name) == ["$ai_generation"])
        #expect(log.records.first?.properties.isEmpty == true)
    }

    @Test("Feature events are listed with their properties")
    func featureEventsKeepProperties() async {
        let log = AnalyticsRecentLog()
        let backend = RecordingAnalyticsBackend(base: NoOpAnalyticsBackend(isConfigured: true), log: log)
        backend.capture(AnalyticsRecord(name: "dock_opened", properties: ["count": AnalyticsValue(2)]))
        await settle(log, count: 1)
        #expect(log.records.map(\.name) == ["dock_opened"])
        #expect(log.records.first?.properties.isEmpty == false)
    }
}
