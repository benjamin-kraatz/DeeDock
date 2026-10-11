import Foundation
import Testing
@testable import DeeDock

/// The crawl of a real (temporary) folder tree: what it walks into, what it finds, and what it leaves out.
struct LookoutCrawlerTests {
    private let folder = LookoutTestFolder()

    private func names(_ report: CrawlReport) -> Set<String> {
        Set(report.candidates.map { String($0.path.dropFirst(folder.path.count + 1)) })
    }

    @Test func hiddenFoldersBundlesAndSecretsAreLeftOut() throws {
        try folder.write("notes/trip.md")
        try folder.write(".hidden/notes.md")
        try folder.write("notes/.draft.md")
        try folder.write("Tool.app/Contents/Resources/readme.txt")
        try folder.write("secret.pem")
        try folder.write("node_modules/pkg/readme.md")
        let report = Crawler.crawl([folder.url], options: IndexOptions(), readsLastUsed: false)
        #expect(names(report) == ["notes/trip.md"])
        #expect(report.skipped["app or bundle"] == 1)
        #expect(report.skipped["key or password file"] == 1)
        #expect(report.skippedFolders["developer folder"] == 1)
    }

    @Test func theHomeLibraryIsNeverWalked() throws {
        try folder.write("Library/Mail/message.txt")
        try folder.write("Documents/Library/catalog.txt")   // a folder of that name elsewhere is fine
        let report = Crawler.crawl([folder.url], options: IndexOptions(), readsLastUsed: false, home: folder.path)
        #expect(names(report) == ["Documents/Library/catalog.txt"])
        #expect(report.skippedFolders["~/Library"] == 1)
    }

    @Test func excludedFoldersAreSkippedUnlessChosenThemselves() throws {
        try folder.write("Downloads/invoice.txt")
        try folder.write("Downloads/Media/movie-notes.txt")
        try folder.write("Downloads/Media/Courses/syllabus.txt")
        var options = IndexOptions()
        options.excludedFolders = [folder.url.appendingPathComponent("Downloads/Media").path]
        let report = Crawler.crawl([folder.url], options: options, readsLastUsed: false)
        #expect(names(report) == ["Downloads/invoice.txt"])
        #expect(report.skippedFolders["excluded folder"] == 1)
        // A folder chosen inside a skipped one is walked whole.
        let courses = folder.url.appendingPathComponent("Downloads/Media/Courses")
        let chosen = Crawler.crawl([folder.url, courses], options: options, readsLastUsed: false)
        #expect(names(chosen) == ["Downloads/invoice.txt", "Downloads/Media/Courses/syllabus.txt"])
    }

    @Test func symbolicLinksAreNeverFollowed() throws {
        let outside = LookoutTestFolder()
        let target = try outside.write("elsewhere/photo-notes.txt")
        try folder.write("real.txt")
        try FileManager.default.createSymbolicLink(at: folder.url.appendingPathComponent("link.txt"),
                                                   withDestinationURL: target)
        try FileManager.default.createSymbolicLink(at: folder.url.appendingPathComponent("linked-folder"),
                                                   withDestinationURL: target.deletingLastPathComponent())
        let report = Crawler.crawl([folder.url], options: IndexOptions(), readsLastUsed: false)
        #expect(names(report) == ["real.txt"])
    }

    @Test func insideACodeProjectOnlyScreenshotsCount() throws {
        try folder.folder("project/.git")
        try folder.write("project/README.md")
        try folder.write("project/assets/logo.png")
        try folder.write("project/docs/Screenshot 2026-10-01 at 9.41.07 PM.png")
        try folder.write("letters/landlord.txt")
        let report = Crawler.crawl([folder.url], options: IndexOptions(), readsLastUsed: false)
        #expect(names(report) == ["project/docs/Screenshot 2026-10-01 at 9.41.07 PM.png", "letters/landlord.txt"])
        #expect(report.skipped["inside a code project"] == 2)
    }

    @Test func nestedRootsAreCrawledOnceAndTheDiskNever() throws {
        let inner = try folder.folder("inner")
        try folder.write("inner/trip.txt")
        let report = Crawler.crawl([folder.url, inner], options: IndexOptions(), readsLastUsed: false)
        #expect(names(report) == ["inner/trip.txt"])
        let disk = Crawler.crawl([URL(fileURLWithPath: "/")], options: IndexOptions(), readsLastUsed: false)
        #expect(disk.candidates.isEmpty)
        #expect(disk.skippedFolders["the whole disk"] == 1)
    }

    @Test func candidatesCarryWhatTheNextSyncCompares() throws {
        let file = try folder.write("notes.txt", Data("twelve bytes".utf8))
        let report = Crawler.crawl([folder.url], options: IndexOptions(), readsLastUsed: false)
        let candidate = try #require(report.candidates.first)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect(candidate.kind == .doc)
        #expect(candidate.size == 12)
        #expect(candidate.inode == (attributes[.systemFileNumber] as? NSNumber)?.uint64Value)
        #expect(candidate.lastUsed == nil)
    }
}
