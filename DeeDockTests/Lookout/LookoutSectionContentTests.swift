import Testing
@testable import DeeDock

/// What the Lookout section shows for each status and search phase.
@MainActor
struct LookoutSectionContentTests {
    private let some = LookoutUIFixtures.results(strong: [LookoutUIFixtures.hit("/Users/t/a.md")])

    private func content(_ status: LookoutStatus, _ phase: LookoutSearch.Phase,
                         _ results: LookoutResultSet = .empty) -> LookoutSectionContent {
        LookoutSectionContent(status: status, phase: phase, results: results)
    }

    @Test("Before setup and while the model downloads, a card replaces results")
    func cards() {
        #expect(content(.notSetUp, .unavailable).body == .promo)
        #expect(content(.waitingForModel, .unavailable).body == .download)
        #expect(content(.off, .unavailable).body == .nothing)
    }

    @Test("Shimmer until something arrives, hits as soon as keyword ones do, the honest state when final and empty")
    func phases() {
        #expect(content(.ready, .warming).body == .skeleton)
        #expect(content(.ready, .keywordOnly).body == .skeleton)
        #expect(content(.ready, .warming, some).body == .results)
        #expect(content(.ready, .keywordOnly, some).body == .results)
        #expect(content(.ready, .done, some).body == .results)
        #expect(content(.ready, .done).body == .empty)
    }

    @Test("Reading, paused and stopped add a note; without an index the note stands alone")
    func notices() {
        #expect(content(.indexing(remaining: 12, progress: nil), .done, some).notice == .indexing(remaining: 12))
        #expect(content(.paused(.onBattery), .done).notice == .paused(.onBattery))
        #expect(content(.indexing(remaining: nil, progress: nil), .unavailable).body == .nothing)
        #expect(content(.ready, .unavailable).body == .empty)
        #expect(content(.ready, .done, some).notice == nil)
    }
}
