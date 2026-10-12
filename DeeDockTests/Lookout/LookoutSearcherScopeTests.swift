import Foundation
import Testing
@testable import DeeDock

/// What `Searcher` searches and what a hit carries: the folder scope, the kinds filter, the settings filter, the
/// segment a hit points at, and lazily loaded vectors.
struct LookoutSearcherScopeTests {
    private let query = LookoutSearchIndex.query

    @Test func aFolderScopeLimitsMeaningAndWords() throws {
        let index = try LookoutSearchIndex()
        try index.background()
        try index.add("inside/meaning.txt", cosine: 0.5)
        try index.add("inside/words.txt", text: "budget")
        try index.add("outside/meaning.txt", cosine: 0.5)
        try index.add("outside/words.txt", text: "budget")
        try index.add("inside-not/words.txt", text: "budget")   // a sibling whose name starts the same
        let results = try index.searcher().search("budget", queryVector: query, scope: index.path("inside"))
        #expect(Set(results.all.map(\.path)) == [index.path("inside/meaning.txt"), index.path("inside/words.txt")])
        let everywhere = try index.searcher().search("budget", queryVector: query)
        #expect(everywhere.count == 5)
    }

    @Test func theScopedFolderIsNeverItsOwnFolderResult() throws {
        let index = try LookoutSearchIndex()
        for name in ["a", "b", "c"] { try index.add("here/\(name).txt", text: "budget") }
        let scoped = try index.searcher().search("budget", queryVector: nil, scope: index.path("here"))
        #expect(scoped.count == 3 && !scoped.all.contains(where: \.isFolder))
        let unscoped = try index.searcher().search("budget", queryVector: nil)
        #expect(unscoped.all.filter(\.isFolder).map(\.path) == [index.path("here")])
    }

    @Test func kindsFilterMeaningAndWords() throws {
        let index = try LookoutSearchIndex()
        try index.background()
        try index.add("k/report.pdf", kind: .pdf, cosine: 0.5, text: "budget", segment: .page, loc: 1)
        try index.add("k/notes.txt", kind: .doc, cosine: 0.5, text: "budget")
        try index.add("k/words.txt", kind: .doc, text: "budget")
        let results = try index.searcher().search("budget", queryVector: query, kinds: [.pdf])
        #expect(results.all.map(\.path) == [index.path("k/report.pdf")])
    }

    @Test func aHitPointsAtThePageThatStandsOutAndQuotesOnlyItsOwnWords() throws {
        let index = try LookoutSearchIndex()
        try index.background()
        let pdf = try index.add("p/manual.pdf", kind: .pdf, text: "an introduction", segment: .page, loc: 1)
        try index.segment(of: pdf, kind: .page, cosine: 0.5, text: "the budget forecast for next year", loc: 7,
                          excerpt: "the budget forecast for next year")
        let hit = try #require(try index.searcher().search("budget", queryVector: query).all.first)
        #expect(hit.segment == .page && hit.page == 7 && hit.loc == 7)
        #expect(hit.snippet?.contains("«budget»") == true)
        #expect(hit.excerpt == "the budget forecast for next year" && hit.displayText == hit.snippet)

        // Words on page 2, meaning on page 5: the hit is page 5, and page 2's words aren't quoted for it.
        let other = try LookoutSearchIndex()
        try other.background()
        let book = try other.add("p/book.pdf", kind: .pdf, text: "budget", segment: .page, loc: 2)
        try other.segment(of: book, kind: .page, cosine: 0.5, loc: 5)
        let split = try #require(try other.searcher().search("budget", queryVector: query).all.first)
        #expect(split.page == 5 && split.snippet == nil && split.match == .both)
    }

    @Test func aPictureBorrowsTheWordsOfItsOCRText() throws {
        let index = try LookoutSearchIndex()
        try index.background()
        let shot = try index.add("s/shot.png", kind: .screenshot, cosine: 0.5, segment: .image, loc: nil)
        try index.segment(of: shot, kind: .ocr, text: "total due 42 euros", loc: nil)
        let hit = try #require(try index.searcher().search("total due", queryVector: query).all.first)
        #expect(hit.segment == .image && hit.snippet?.contains("«total»") == true)
    }

    @Test func theSettingsFilterDropsFilesBeforeFoldersAreGrouped() throws {
        let index = try LookoutSearchIndex()
        for name in ["one.txt", "two.txt", "skipped.md"] {
            try index.folder.write("grp/\(name)")
            try index.add("grp/\(name)", text: "budget")
        }
        try index.add("grp/gone.txt", text: "budget")   // indexed, but no longer on disk
        let filter = LookoutSearchFilter(folders: [index.folder.path], excludedExtensions: ["md"])
        let results = try index.searcher().search("budget", queryVector: nil, filter: filter)
        #expect(Set(results.all.map(\.path)) == [index.path("grp/one.txt"), index.path("grp/two.txt")])

        let elsewhere = LookoutSearchFilter(folders: ["/somewhere/else"], requireExisting: false)
        #expect(try index.searcher().search("budget", queryVector: nil, filter: elsewhere).isEmpty)
    }

    /// More than `Searcher.wordFiles` strong word matches the filter turns down, above one weaker match it allows.
    private static let crowd = Searcher.wordFiles + 20
    /// A weaker match: the word once in a long passage ranks below the crowd's short "budget budget".
    private static let weaker = "budget " + Array(repeating: "quarterly notes about the garden and the roof", count: 30)
        .joined(separator: " ")

    @Test func deletedFilesDontUseUpTheWordBudget() throws {
        let index = try LookoutSearchIndex()
        for number in 0..<Self.crowd { try index.add("docs/gone-\(number).txt", text: "budget budget") }   // not on disk
        try index.folder.write("docs/kept.txt")
        try index.add("docs/kept.txt", text: Self.weaker)
        let filter = LookoutSearchFilter(folders: [index.folder.path])
        let results = try index.searcher().search("budget", queryVector: nil, filter: filter)
        #expect(results.all.map(\.path) == [index.path("docs/kept.txt")])
    }

    @Test func excludedFoldersAndTypesDontUseUpTheWordBudget() throws {
        let index = try LookoutSearchIndex()
        for number in 0..<Self.crowd {
            try index.add("root/Media/clip-\(number).txt", text: "budget budget")
            try index.add("root/notes-\(number).md", text: "budget budget")
        }
        try index.add("root/kept.txt", text: Self.weaker)
        try index.add("root/Media/Courses/syllabus.txt", text: Self.weaker)   // chosen inside the skip: searched
        try index.add("elsewhere/other.txt", text: "budget budget")
        let filter = LookoutSearchFilter(folders: [index.path("root"), index.path("root/Media/Courses")],
                                         skipped: [index.path("root/Media")], excludedExtensions: ["md"],
                                         requireExisting: false)
        let results = try index.searcher().search("budget", queryVector: nil, filter: filter)
        #expect(Set(results.all.map(\.path)) == [index.path("root/kept.txt"), index.path("root/Media/Courses/syllabus.txt")])
    }

    /// A folder on an unplugged drive keeps its rows, but its files can't be opened, so they show no results until the
    /// drive is back. Then they return as they were, with nothing read again (Settings: "results return when it's
    /// back").
    @Test func filesOnAnUnpluggedDriveReturnWhenItsBack() throws {
        let index = try LookoutSearchIndex()
        try index.add("Drive/Scans/invoice.txt", text: "budget")
        let filter = LookoutSearchFilter(folders: [index.path("Drive")])
        #expect(try index.searcher().search("budget", queryVector: nil, filter: filter).isEmpty)
        #expect(try index.store.file(at: index.path("Drive/Scans/invoice.txt"))?.state == "done", "kept")
        try index.folder.write("Drive/Scans/invoice.txt")   // connected again
        let back = try index.searcher().search("budget", queryVector: nil, filter: filter)
        #expect(back.all.map(\.path) == [index.path("Drive/Scans/invoice.txt")])
    }

    @Test func vectorsLoadForTheFirstMeaningSearchAndCanBeReleased() throws {
        let index = try LookoutSearchIndex()
        try index.background(30)
        try index.add("v/target.txt", cosine: 0.5, text: "budget")
        let searcher = try index.searcher(loadVectors: false)
        #expect(!searcher.vectorsLoaded)
        #expect(try searcher.search("budget", queryVector: nil).count == 1)
        #expect(!searcher.vectorsLoaded)   // keyword search needs no vectors
        _ = try searcher.search("budget", queryVector: query)
        #expect(searcher.vectorsLoaded && searcher.vectorCount == 31)
        searcher.releaseVectors()
        #expect(!searcher.vectorsLoaded && searcher.vectorCount == 0)
        #expect(try searcher.search("budget", queryVector: nil).count == 1)
        try index.add("v/later.txt", cosine: 0.4)
        try searcher.reload()
        #expect(searcher.vectorCount == 32)
    }
}
