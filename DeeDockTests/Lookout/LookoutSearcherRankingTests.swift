import Foundation
import Testing
@testable import DeeDock

/// How `Searcher` ranks: the meaning gate, word coverage, lookups, the kind hint and the strong/weak split, on a
/// temporary index of synthetic vectors (`LookoutSearchIndex`).
struct LookoutSearcherRankingTests {
    private let query = LookoutSearchIndex.query

    @Test func onlyFilesThatStandOutInMeaningQualify() throws {
        let index = try LookoutSearchIndex()
        try index.background()
        try index.add("docs/target.txt", cosine: 0.5)
        try index.add("docs/near.txt", cosine: 0.065)   // above every background file, but not by two deviations
        let results = try index.searcher().search("anything", queryVector: query)
        let paths = results.all.map(\.path)
        #expect(paths == [index.path("docs/target.txt")])
        let hit = try #require(results.all.first)
        #expect(hit.match == .meaning && hit.coverage == 0 && hit.keywordRank == nil)
        let z = try #require(hit.z)
        #expect(z >= LookoutRanking.zGate)
        #expect(abs(hit.score - z) < 1e-9)   // meaning alone: z × 1
        #expect(results.usedMeaning && !results.isLookup)
    }

    @Test func withoutAVectorNothingQualifiesByMeaning() throws {
        let index = try LookoutSearchIndex()
        try index.background()
        try index.add("docs/target.txt", cosine: 0.5)
        let results = try index.searcher().search("anything", queryVector: nil)
        #expect(results.isEmpty && !results.usedMeaning)
    }

    @Test func wordsCountByCoverageAndHalfTheWordsIsTheGate() throws {
        let index = try LookoutSearchIndex()
        try index.add("a/all.txt", text: "the quarterly invoice for march")
        try index.add("a/half.txt", text: "an invoice, nothing else")
        try index.add("a/none.txt", text: "holiday pictures")
        let results = try index.searcher().search("quarterly invoice", queryVector: nil)
        let all = try #require(results.all.first { $0.path == index.path("a/all.txt") })
        let half = try #require(results.all.first { $0.path == index.path("a/half.txt") })
        #expect(results.count == 2)
        #expect(all.coverage == 1 && abs(all.score - LookoutRanking.wordWeight) < 1e-9)
        #expect(abs(half.coverage - 0.5) < 1e-9)
        #expect(abs(half.score - LookoutRanking.wordWeight * pow(0.5, 1.5)) < 1e-9)
        #expect(all.match == .words && half.match == .words)
        // 0.71 is under half of 2.0: the half match folds under weaker matches.
        #expect(results.strong.map(\.path) == [all.path] && results.weak.map(\.path) == [half.path])

        let three = try index.searcher().search("quarterly invoice march", queryVector: nil)
        #expect(three.all.map(\.path) == [all.path])   // a third of the words isn't enough
    }

    @Test func meaningAndWordsAddUpAndSayBoth() throws {
        let index = try LookoutSearchIndex()
        try index.background()
        try index.add("docs/both.txt", cosine: 0.5, text: "shipped on monday")
        let hit = try #require(try index.searcher().search("shipped", queryVector: query).all.first)
        let z = try #require(hit.z)
        #expect(hit.match == .both)
        #expect(abs(hit.score - (z + LookoutRanking.wordWeight)) < 1e-9)
    }

    @Test func aLookupWeighsWordsDoubleAndMeaningHalf() throws {
        let index = try LookoutSearchIndex()
        try index.background()
        try index.add("codes/order.txt", cosine: 0.5, text: "order K7Q2LM shipped")
        let results = try index.searcher().search("K7Q2LM", queryVector: query)
        #expect(results.isLookup && results.terms == ["k7q2lm"])
        let hit = try #require(results.all.first)
        let z = try #require(hit.z)
        #expect(abs(hit.score - (LookoutRanking.lookupMeaningWeight * z + 4)) < 1e-9)
        #expect(Searcher.isLookup(["4815162342"]) && Searcher.isLookup(["trx50"]))
        #expect(!Searcher.isLookup(["invoice"]) && !Searcher.isLookup(["v2", "invoice"]) && !Searcher.isLookup([]))
    }

    @Test func theKindAQueryNamesGetsAPointMore() throws {
        let index = try LookoutSearchIndex()
        try index.add("s/lunch.png", kind: .screenshot, text: "receipts from lunch", segment: .ocr, loc: nil)
        try index.add("s/notes.txt", kind: .doc, text: "receipts to file")
        let results = try index.searcher().search("screenshot of receipts", queryVector: nil)
        #expect(results.terms == ["receipts"])   // kind words and stopwords aren't searched for
        let shot = try #require(results.all.first)
        #expect(shot.kind == .screenshot && abs(shot.score - (LookoutRanking.wordWeight + 1)) < 1e-9)
        #expect(results.all.last?.kind == .doc && abs((results.all.last?.score ?? 0) - LookoutRanking.wordWeight) < 1e-9)
    }

    @Test func strongHitsScoreAtLeastHalfTheTop() {
        func hit(_ score: Double) -> LookoutHit {
            LookoutHit(path: "/x/\(score)", kind: .doc, folder: nil, score: score, z: nil, cosine: nil, coverage: 1,
                       keywordRank: 1, match: .words, segment: .chunk, segmentID: 1, loc: nil, locEnd: nil,
                       snippet: nil, excerpt: nil, modified: 0, size: 0, info: [:])
        }
        #expect(LookoutRanking.strongRatio == 0.5)
        #expect(Searcher.strongCount([hit(4), hit(2), hit(1.99)]) == 2)
        #expect(Searcher.strongCount([hit(0), hit(0)]) == 2)   // no positive top: nothing is folded
        let set = LookoutResultSet(ranked: [hit(4), hit(2), hit(1.99)], terms: [], isLookup: false, usedMeaning: false)
        #expect(set.strong.count == 2 && set.weak.count == 1)
    }
}
