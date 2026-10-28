import Foundation
import Testing
@testable import DeeDock

/// Searching with a vector alone (`Searcher.similar`): meaning only, pictures and documents ranked and split on their
/// own, the query's own kind first, and never the file searched with. Also which stored vector Find Similar reuses
/// (`Searcher.similarSource`). On a temporary index of synthetic vectors (`LookoutSearchIndex`).
struct LookoutSimilarSearchTests {
    private let query = LookoutSearchIndex.query

    /// Pictures far above documents, as a picture query's cosines are: two strong pictures and a trailing screenshot,
    /// two documents well below the pictures but close to each other.
    private func mixedIndex() throws -> LookoutSearchIndex {
        let index = try LookoutSearchIndex()
        try index.background(200)
        try index.add("pics/a.heic", kind: .image, cosine: 0.9, segment: .image, loc: nil)
        try index.add("pics/b.heic", kind: .image, cosine: 0.6, segment: .image, loc: nil)
        try index.add("shots/c.png", kind: .screenshot, cosine: 0.35, segment: .image, loc: nil)
        try index.add("docs/d.pdf", kind: .pdf, cosine: 0.35, segment: .page, loc: 3)
        try index.add("docs/e.md", kind: .doc, cosine: 0.3)
        return index
    }

    @Test func eachGroupSplitsAtItsOwnTopScore() throws {
        let index = try mixedIndex()
        let results = try index.searcher().similar(to: query, queryIsPicture: true)
        let pictures = try #require(results.groups.first)
        let documents = try #require(results.groups.last)
        #expect(pictures.kind == .pictures && documents.kind == .documents)
        #expect(pictures.strong.map(\.path) == [index.path("pics/a.heic"), index.path("pics/b.heic")])
        #expect(pictures.weak.map(\.path) == [index.path("shots/c.png")])
        #expect(documents.strong.map(\.path) == [index.path("docs/d.pdf"), index.path("docs/e.md")])
        #expect(documents.weak.isEmpty)
        // One list would have folded both documents under the top picture.
        let top = try #require(pictures.strong.first?.score)
        #expect(documents.strong.allSatisfy { $0.score < top * LookoutRanking.strongRatio })
        // No words: the score is the meaning z alone, and every hit says so.
        for hit in results.all {
            #expect(hit.match == .meaning && hit.coverage == 0 && hit.snippet == nil)
            #expect(hit.z.map { abs($0 - hit.score) < 1e-9 } == true)
            #expect((hit.z ?? 0) >= LookoutRanking.zGate)
        }
        #expect(results.all.allSatisfy { !$0.path.contains("/background/") })
    }

    @Test func theQuerysOwnKindComesFirst() throws {
        let index = try mixedIndex()
        let searcher = try index.searcher()
        #expect(try searcher.similar(to: query, queryIsPicture: true).groups.map(\.kind) == [.pictures, .documents])
        #expect(try searcher.similar(to: query, queryIsPicture: false).groups.map(\.kind) == [.documents, .pictures])
        #expect(LookoutSimilarResults.order(queryIsPicture: false) == [.documents, .pictures])
        #expect(LookoutSimilarResults(queryIsPicture: false).groups.map(\.kind) == [.documents, .pictures])
    }

    @Test func theFileSearchedWithNeverAppears() throws {
        let index = try LookoutSearchIndex()
        try index.background(200)
        for name in ["one", "two", "three"] {
            try index.add("Sylt/\(name).heic", kind: .image, cosine: 0.8, segment: .image, loc: nil)
        }
        let all = try index.searcher().similar(to: query, queryIsPicture: true)
        // Three matching pictures make their folder a result.
        #expect(all.groups[0].all.contains { $0.path == index.path("Sylt") && $0.isFolder })

        let mine = index.path("Sylt/one.heic")
        let results = try index.searcher().similar(to: query, queryIsPicture: true, excluding: [mine])
        #expect(!results.all.contains { $0.path == mine })
        #expect(results.groups[0].all.map(\.path) == [index.path("Sylt/three.heic"), index.path("Sylt/two.heic")])
        // Without it, two pictures are left: too few for the folder.
        #expect(!results.all.contains { $0.isFolder })
    }

    @Test func aGroupWithNothingStandingOutIsEmpty() throws {
        let index = try LookoutSearchIndex()
        try index.background(200)
        try index.add("docs/d.md", kind: .doc, cosine: 0.4)
        try index.add("pics/faint.heic", kind: .image, cosine: 0.05, segment: .image, loc: nil)
        let results = try index.searcher().similar(to: query, queryIsPicture: true)
        #expect(results.groups.map(\.kind) == [.pictures, .documents])
        #expect(results.groups[0].isEmpty)
        #expect(results.groups[1].strong.map(\.path) == [index.path("docs/d.md")])
        #expect(!results.hasNoStrongHits)

        let nothing = try LookoutSearchIndex()
        try nothing.background(200)
        let none = try nothing.searcher().similar(to: query, queryIsPicture: true)
        #expect(none.hasNoStrongHits)
    }

    @Test func scopeAndFilterApply() throws {
        let index = try mixedIndex()
        let scoped = try index.searcher().similar(to: query, queryIsPicture: true, scope: index.path("docs"))
        #expect(scoped.all.map(\.path) == [index.path("docs/d.pdf"), index.path("docs/e.md")])
        let filter = LookoutSearchFilter(folders: [index.path("pics")], requireExisting: false)
        let filtered = try index.searcher().similar(to: query, queryIsPicture: true, filter: filter)
        #expect(filtered.all.map(\.path) == [index.path("pics/a.heic"), index.path("pics/b.heic")])
    }

    @Test func aHitPointsAtItsBestSegment() throws {
        let index = try LookoutSearchIndex()
        try index.background(200)
        let pdf = try index.add("docs/lease.pdf", kind: .pdf, cosine: 0.1, segment: .page, loc: 1)
        try index.segment(of: pdf, kind: .page, cosine: 0.7, loc: 7, excerpt: "§ 12 Tierhaltung")
        let hit = try #require(try index.searcher().similar(to: query, queryIsPicture: false).all.first)
        #expect(hit.page == 7 && hit.excerpt == "§ 12 Tierhaltung")
    }

    // MARK: Words beside the picture

    @Test func wordsBesideThePictureMoveItsResults() throws {
        let index = try LookoutSearchIndex()
        try index.background(200)
        try index.add("pics/a.heic", kind: .image, cosine: 0.8, segment: .image, loc: nil)
        try index.add("pics/b.heic", kind: .image, cosine: 0.6, segment: .image, loc: nil)
        let searcher = try index.searcher()
        let alone = try searcher.similar(to: query, queryIsPicture: true)
        #expect(alone.groups[0].all.map(\.path) == [index.path("pics/a.heic"), index.path("pics/b.heic")])
        #expect(!alone.hasWords)

        // Words that describe b and not the picture: at the default weight they lift b above a.
        var words = LookoutSimilarWords(text: "at night", vector: index.vector(towards: "pics/b.heic"))
        let both = try searcher.similar(to: query, queryIsPicture: true, words: words)
        #expect(both.groups[0].all.first?.path == index.path("pics/b.heic"))
        #expect(both.words == "at night" && both.hasWords && both.terms == ["night"])
        // Neither name has the word: both still match by meaning, on the blend's own scale.
        #expect(both.all.allSatisfy { $0.match == .meaning && ($0.z ?? 0) >= LookoutRanking.zGate })

        // Toward the picture, the picture's order comes back.
        words.weight = LookoutRanking.pictureWordsWeights.lowerBound
        let leaning = try searcher.similar(to: query, queryIsPicture: true, words: words)
        #expect(leaning.groups[0].all.first?.path == index.path("pics/a.heic"))
    }

    @Test func typedWordsCountAsKeywords() throws {
        let index = try LookoutSearchIndex()
        try index.background(200)
        try index.add("pics/a.heic", kind: .image, cosine: 0.8, segment: .image, loc: nil)
        // Nothing like the picture, but its name has the word.
        try index.add("pics/Sunset Westerland.jpg", kind: .image, cosine: 0.02, segment: .image, loc: nil)
        // The encoder failed: the words count as keywords only, and "but" only ties them to the picture.
        let words = LookoutSimilarWords(text: "but at sunset", vector: nil)
        let results = try index.searcher().similar(to: query, queryIsPicture: true, words: words)
        #expect(results.terms == ["sunset"] && !results.isLookup)
        let named = try #require(results.all.first { $0.path == index.path("pics/Sunset Westerland.jpg") })
        #expect(named.match == .words && named.coverage == 1 && named.keywordRank == 1)
        // Scored as a search by words scores it: its little meaning plus the full word bonus.
        #expect(abs(named.score - (max(named.z ?? 0, 0) + LookoutRanking.wordWeight)) < 1e-9)
        let alike = try #require(results.all.first { $0.path == index.path("pics/a.heic") })
        #expect(alike.match == .meaning && alike.coverage == 0)
    }

    @Test func theFileSearchedWithStaysOutOfTheWordMatches() throws {
        let index = try LookoutSearchIndex()
        try index.background(200)
        try index.add("pics/Sunset.jpg", kind: .image, cosine: 0.9, segment: .image, loc: nil)
        try index.add("pics/Sunset 2.jpg", kind: .image, cosine: 0.7, segment: .image, loc: nil)
        let words = LookoutSimilarWords(text: "sunset", vector: nil)
        let results = try index.searcher().similar(to: query, queryIsPicture: true, words: words,
                                                   excluding: [index.path("pics/Sunset.jpg")])
        #expect(results.all.map(\.path) == [index.path("pics/Sunset 2.jpg")])
        #expect(results.all.first?.match == .both)
    }

    @Test func theBlendKeepsTheGatesScale() {
        let scores: [Float] = (0..<200).map { Float(sin(Double($0)) * 0.05) } + [0.6, 0.4]
        let other: [Float] = (0..<200).map { Float(cos(Double($0) * 1.7) * 0.05) } + [0.1, 0.7]
        let modality = [Modality](repeating: .image, count: scores.count)
        let picture = Searcher.meaning(scores, modality), words = Searcher.meaning(other, modality)
        let blended = Searcher.blend(picture, words, weight: 0.4)
        let mean = blended.reduce(0, +) / Double(blended.count)
        let deviation = (blended.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(blended.count)).squareRoot()
        #expect(abs(mean) < 1e-9 && abs(deviation - 1) < 1e-9)
        // Each side alone is the side itself: already on its own scale.
        #expect(zip(Searcher.blend(picture, words, weight: 0), picture).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(zip(Searcher.blend(picture, words, weight: 1), words).allSatisfy { abs($0 - $1) < 1e-9 })
        // The last file, close to the words, rises above the one close to the picture.
        #expect(blended[201] > blended[200])
    }

    // MARK: Find Similar's vector

    @Test func findSimilarPrefersTheMatchedSegment() throws {
        let index = try LookoutSearchIndex()
        let pdf = try index.add("docs/lease.pdf", kind: .pdf, cosine: 0.1, segment: .page, loc: 1)
        try index.segment(of: pdf, kind: .page, cosine: 0.7, loc: 7)
        let pages = try segmentIDs(index, file: pdf, kind: .page)
        let searcher = try index.searcher()
        let page7 = try #require(try searcher.similarSource(path: index.path("docs/lease.pdf"),
                                                            preferredSegment: pages[1]))
        #expect(page7.page == 7 && page7.modality == .text && page7.segment == .page)
        #expect(abs(page7.vector[0] - 0.7) < 0.01)
        // Without a preference, or with one that has no vector, the first segment with a vector.
        let first = try #require(try searcher.similarSource(path: index.path("docs/lease.pdf")))
        #expect(first.page == 1)
        let unknown = try #require(try searcher.similarSource(path: index.path("docs/lease.pdf"),
                                                              preferredSegment: 999_999))
        #expect(unknown.page == 1)
    }

    @Test func findSimilarFallsBackToThePicture() throws {
        let index = try LookoutSearchIndex()
        // A screenshot's OCR words come first and have no vector; its picture does.
        let shot = try index.add("s/shot.png", kind: .screenshot, text: "Payment declined", segment: .ocr, loc: nil)
        try index.segment(of: shot, kind: .image, cosine: 0.6)
        let ocr = try segmentIDs(index, file: shot, kind: .ocr)
        let searcher = try index.searcher()
        let source = try #require(try searcher.similarSource(path: index.path("s/shot.png"),
                                                             preferredSegment: ocr[0]))
        #expect(source.segment == .image && source.modality == .image && source.page == nil)
        #expect(source.path == index.path("s/shot.png"))
        #expect(try searcher.similarSource(path: index.path("s/missing.png")) == nil)
        #expect(try searcher.indexedPaths([index.path("s/shot.png"), index.path("s/missing.png")])
            == [index.path("s/shot.png")])
    }

    @Test func aFileWithoutVectorsHasNothingToReuse() throws {
        let index = try LookoutSearchIndex()
        try index.add("docs/words-only.md", text: "nothing but words")
        let searcher = try index.searcher()
        #expect(try searcher.similarSource(path: index.path("docs/words-only.md")) == nil)
        #expect(try searcher.indexedPaths([index.path("docs/words-only.md")]).isEmpty)
    }

    /// The ids of a file's segments of `kind`, in order (the index also gives every file a name segment).
    private func segmentIDs(_ index: LookoutSearchIndex, file: Int64, kind: SegmentKind) throws -> [Int64] {
        var ids: [Int64] = []
        try index.store.db.query("SELECT id FROM segments WHERE file = ? AND kind = ? ORDER BY id",
                                 [.int(file), .text(kind.rawValue)]) { ids.append($0.int(0)) }
        return ids
    }
}
