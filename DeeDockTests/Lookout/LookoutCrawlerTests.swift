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

    @Test func theHomeFolderAndItsLibraryAreNeverWalked() throws {
        try folder.write("Library/Mail/message.txt")
        try folder.write("Documents/Library/catalog.txt")   // a folder of that name elsewhere is fine
        let crawl = { (relative: String) in
            Crawler.crawl([relative.isEmpty ? folder.url : folder.url.appendingPathComponent(relative)],
                          options: IndexOptions(), readsLastUsed: false, home: folder.path)
        }
        let home = crawl("")
        #expect(home.candidates.isEmpty && home.roots.isEmpty && home.skippedFolders["the home folder"] == 1)
        let library = crawl("Library/Mail")
        #expect(library.candidates.isEmpty && library.skippedFolders["~/Library"] == 1)
        let documents = crawl("Documents")
        #expect(names(documents) == ["Documents/Library/catalog.txt"])
        #expect(documents.roots == [folder.path + "/Documents"])
    }

    @Test func aChosenFolderThatBecameALinkIsCheckedWhereItLeads() throws {
        try folder.write("Library/Keychains/notes.txt")
        try folder.write("Letters/landlord.txt")
        let notes = folder.url.appendingPathComponent("Notes")
        try FileManager.default.createSymbolicLink(at: notes, withDestinationURL: folder.url.appendingPathComponent("Library"))
        let report = Crawler.crawl([notes], options: IndexOptions(), readsLastUsed: false, home: folder.path)
        #expect(report.candidates.isEmpty && report.roots.isEmpty)
        #expect(report.skippedFolders["~/Library"] == 1)

        // A link to an ordinary folder is walked where it leads, and reports real paths.
        let letters = folder.url.appendingPathComponent("Mail")
        try FileManager.default.createSymbolicLink(at: letters, withDestinationURL: folder.url.appendingPathComponent("Letters"))
        let linked = Crawler.crawl([letters], options: IndexOptions(), readsLastUsed: false, home: folder.path)
        #expect(names(linked) == ["Letters/landlord.txt"])
    }

    @Test func aCloudStorageFolderIsWalkedThroughItsLink() throws {
        try folder.write("Library/CloudStorage/Dropbox/Taxes/receipt.txt")
        try folder.write("Library/CloudStorage/.hidden-cache/state.txt")
        let link = folder.url.appendingPathComponent("Dropbox")
        try FileManager.default.createSymbolicLink(at: link,
                                                   withDestinationURL: folder.url.appendingPathComponent("Library/CloudStorage/Dropbox"))
        let report = Crawler.crawl([link], options: IndexOptions(), readsLastUsed: false, home: folder.path)
        #expect(names(report) == ["Library/CloudStorage/Dropbox/Taxes/receipt.txt"])
        #expect(report.roots == [folder.path + "/Library/CloudStorage/Dropbox"])
        // CloudStorage itself is not a root.
        let storage = Crawler.crawl([folder.url.appendingPathComponent("Library/CloudStorage")], options: IndexOptions(),
                                    readsLastUsed: false, home: folder.path)
        #expect(storage.candidates.isEmpty && storage.skippedFolders["~/Library"] == 1)
    }

    @Test func savedRootsAreCheckedAgainWhereTheyLead() throws {
        try folder.write(".hidden/keys.txt")
        let documents = try folder.folder("Documents")
        let notes = folder.url.appendingPathComponent("Notes")
        try FileManager.default.createSymbolicLink(at: notes, withDestinationURL: folder.url.appendingPathComponent(".hidden"))
        let configuration = LookoutIndexConfiguration(roots: [notes.path, documents.path, "/", "/System/Library"],
                                                      modelsFolder: "", indexFolder: "", backfillAllowed: true)
        #expect(configuration.allowedRoots.map(\.path) == [documents.path])
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
