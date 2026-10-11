import Foundation
import Testing
@testable import DeeDock

/// `LookoutSearch`'s two passes and generations over a fake reader and encoder: keyword results first, hybrid results
/// last, and nothing from a query that was replaced.
@MainActor struct LookoutSearchTests {
    private let reader = FakeIndexReader()
    private let encoder = FakeQueryEncoder()

    private func search() -> LookoutSearch {
        let search = LookoutSearch(reader: reader, encoder: encoder, debounce: .zero)
        search.isAvailable = true
        return search
    }

    @Test func keywordResultsComeFirstThenTheHybridOnes() async {
        encoder.delay = .milliseconds(150)
        let search = search()
        search.search("  budget ", scope: .thisMac)
        #expect(await eventually { search.phase == .keywordOnly })
        #expect(search.results.terms == ["budget"] && !search.results.usedMeaning)
        #expect(await eventually { search.phase == .done })
        #expect(search.results.usedMeaning)
        let requests = await reader.requests
        #expect(requests.map(\.prefixLast) == [true, false])   // the half-typed last word, then whole words
        #expect(requests.last?.vector?.count == Vectors.dimension && requests.first?.vector == nil)
        #expect(encoder.embedded == ["budget"])
    }

    @Test func aColdEncoderShowsAsWarming() async {
        encoder.isWarm = false
        encoder.delay = .milliseconds(150)
        let search = search()
        search.search("budget", scope: .thisMac)
        #expect(search.phase == .warming)
        #expect(await eventually { search.results.terms == ["budget"] })
        #expect(search.phase == .warming)   // keyword results show, meaning still waits
        #expect(await eventually { search.phase == .done })
    }

    @Test func aFailedEncoderEndsWithKeywordResults() async {
        encoder.fails = true
        let search = search()
        search.search("budget", scope: .thisMac)
        #expect(await eventually { search.phase == .done })
        #expect(!search.results.usedMeaning && search.results.terms == ["budget"])
    }

    @Test func aReplacedQueryNeverPublishes() async {
        await reader.setKeywordDelay(.milliseconds(200), for: "alpha")
        encoder.delays = ["alpha": .milliseconds(200)]
        let search = search()
        search.search("alpha", scope: .thisMac)
        #expect(await eventually { await reader.requests.contains { $0.text == "alpha" } })
        search.search("beta", scope: .thisMac)
        #expect(await eventually { search.phase == .done && search.results.terms == ["beta"] })
        // Long enough for alpha's keyword pass and embedding to have finished.
        try? await Task.sleep(for: .milliseconds(400))
        #expect(search.phase == .done && search.results.terms == ["beta"])
        #expect(await reader.requests.filter { $0.text == "alpha" }.count == 1)   // its hybrid pass never ran
    }

    @Test func aReplacedEmbeddingNeverPublishes() async {
        encoder.delays = ["alpha": .milliseconds(200)]
        let search = search()
        search.search("alpha", scope: .thisMac)
        #expect(await eventually { search.results.terms == ["alpha"] })   // alpha's keyword results are out
        search.search("beta", scope: .thisMac)
        #expect(await eventually { search.phase == .done && search.results.terms == ["beta"] })
        try? await Task.sleep(for: .milliseconds(300))
        #expect(search.results.terms == ["beta"])
    }

    @Test func aFolderScopeIsPassedOnAsItsPath() async {
        let search = search()
        search.search("budget", scope: .folder(URL(fileURLWithPath: "/Users/x/Documents", isDirectory: true)))
        #expect(await eventually { search.phase == .done })
        #expect(await reader.requests.allSatisfy { $0.scope == "/Users/x/Documents" })
        search.search("budget", scope: .thisMac)
        #expect(await eventually { await reader.requests.count == 4 })
        #expect(await reader.requests.last?.scope == nil)
    }

    @Test func emptyUnavailableAndNoIndex() async {
        let search = search()
        search.search("   ", scope: .thisMac)
        #expect(search.phase == .idle && search.results.isEmpty)

        search.isAvailable = false
        search.search("budget", scope: .thisMac)
        #expect(search.phase == .unavailable)
        #expect(await reader.requests.isEmpty)

        await reader.setAvailable(false)
        search.isAvailable = true   // re-runs the last query
        #expect(await eventually { await reader.requests.count == 1 })
        #expect(await eventually { search.phase == .unavailable })

        await reader.setAvailable(true)
        search.refresh()
        #expect(await eventually { search.phase == .done && search.results.terms == ["budget"] })
    }
}
