import Testing
@testable import DeeDock

/// `lookout_result_opened` and the Lookout search counters: tokens only, never the query, a name or a path.
@MainActor
struct LookoutAnalyticsTests {
    private let secretQuery = "dog on the beach at grandma's"
    private let secretPath = "/Users/tester/Desktop/Grandma Sylt 2026/IMG_4821.HEIC"

    private func values(_ event: AnalyticsEvent) -> [String: String] {
        event.properties.values.mapValues(\.displayText)
    }

    @Test("Kinds map to their tokens, folders included")
    func kinds() {
        #expect(AnalyticsLookoutKind(LookoutUIFixtures.hit("/a.png", kind: .screenshot)).rawValue == "screenshot")
        #expect(AnalyticsLookoutKind(LookoutUIFixtures.hit("/a.heic", kind: .image)).rawValue == "image")
        #expect(AnalyticsLookoutKind(LookoutUIFixtures.hit("/a.pdf", kind: .pdf)).rawValue == "pdf")
        #expect(AnalyticsLookoutKind(LookoutUIFixtures.hit("/a.md", kind: .doc)).rawValue == "doc")
        #expect(AnalyticsLookoutKind(LookoutUIFixtures.hit("/Taxes", folderFiles: 4)).rawValue == "folder")
    }

    @Test("Matches map to meaning, words and both")
    func matches() {
        #expect([LookoutHit.Match.meaning, .words, .both].map { AnalyticsLookoutMatch($0).rawValue }
            == ["meaning", "words", "both"])
    }

    @Test("A Lookout open reports section, rank, kind, match, scope and lookup")
    func lookoutOpen() {
        let hit = LookoutUIFixtures.hit(secretPath, kind: .image, match: .both, segment: .image)
        let event = LookoutAnalytics.opened(hit, section: .weak, rank: 2, scope: .folder, isLookup: true)
        #expect(event.name == "lookout_result_opened")
        #expect(values(event) == ["section": "weak", "rank": "2", "kind": "image", "match": "both", "scope": "folder",
                                  "is_lookup": "true", "query": "text"])
    }

    @Test("A name open has no kind or match")
    func nameOpen() {
        let event = LookoutAnalytics.openedName(rank: 1, scope: .thisMac, isLookup: false)
        #expect(values(event) == ["section": "names", "rank": "1", "scope": "this_mac", "is_lookup": "false",
                                  "query": "text"])
    }

    @Test("No property ever carries the query, a name or a path")
    func noUserContent() {
        let hit = LookoutUIFixtures.hit(secretPath, kind: .pdf, match: .words, segment: .page, loc: 7,
                                        snippet: "«\(secretQuery)»", excerpt: secretQuery)
        let folder = LookoutUIFixtures.hit("/Users/tester/Desktop/Grandma Sylt 2026", folderFiles: 5)
        let events = [LookoutAnalytics.opened(hit, section: .strong, rank: 1, scope: .thisMac, isLookup: false),
                      LookoutAnalytics.opened(folder, section: .strong, rank: 3, scope: .folder, isLookup: true),
                      LookoutAnalytics.openedName(rank: 4, scope: .thisMac, isLookup: false)]
        let forbidden = [secretQuery, secretPath, "Grandma", "IMG_4821", "/Users", "tester", "dog", "beach"]
        for event in events {
            for value in values(event).values {
                #expect(!forbidden.contains { value.localizedCaseInsensitiveContains($0) }, "\(event.name): \(value)")
            }
            #expect(Set(values(event).keys).isSubset(of: ["section", "rank", "kind", "match", "scope", "is_lookup",
                                                          "query"]))
        }
    }

    @Test("A search counts as shown or empty only once Lookout's final results arrived")
    func searchCounters() {
        let some = LookoutUIFixtures.results(strong: [LookoutUIFixtures.hit("/a.md")])
        #expect(LookoutAnalytics.searchCounter(phase: .done, results: some) == .lookoutSearchWithResults)
        #expect(LookoutAnalytics.searchCounter(phase: .done, results: .empty) == .lookoutSearchWithoutResults)
        #expect(LookoutAnalytics.searchCounter(phase: .keywordOnly, results: some) == nil)
        #expect(LookoutAnalytics.searchCounter(phase: .warming, results: .empty) == nil)
        #expect(LookoutAnalytics.searchCounter(phase: .unavailable, results: .empty) == nil)
        #expect(AnalyticsCounter.lookoutSearchWithResults.key == "lookout_search_with_results")
        #expect(AnalyticsCounter.lookoutSearchWithoutResults.key == "lookout_search_without_results")
        #expect(AnalyticsCounter.lookoutWeakMatchesExpanded.key == "lookout_weak_matches_expanded")
    }
}
