import Darwin
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import DeeDock

/// The document types Lookout reads beyond the first ones, SVG left out, and what an existing index does about them on
/// its next sync (`Rules`, `Crawler`, `QueuedFileGate`, `DocumentText`, `IndexSync`).
struct LookoutDocumentTypesTests {
    private let folder = LookoutTestFolder()

    private func classify(_ url: URL) -> Rules.Classification {
        Rules.classify(url, type: UTType(filenameExtension: url.pathExtension), options: IndexOptions())
    }

    private func names(_ report: CrawlReport) -> Set<String> {
        Set(report.candidates.map { String($0.path.dropFirst(folder.path.count + 1)) })
    }

    // MARK: Rules and the crawl

    @Test func markupSubtitlesLaTeXAndWebArchivesAreDocuments() throws {
        for name in ["guide.rst", "book.adoc", "book.asciidoc", "plan.org", "paper.tex", "paper.latex",
                     "notes.textile", "page.xhtml", "post.mdx", "talk.srt", "talk.vtt", "saved.webarchive"] {
            #expect(classify(try folder.write(name)) == .index(.doc), "\(name)")
        }
    }

    @Test func svgIsQuietlyIgnoredAndXMLStaysSkipped() throws {
        #expect(classify(try folder.write("logo.svg")) == .ignore)
        #expect(classify(try folder.write("logo.svgz")) == .ignore)
        #expect(classify(try folder.write("feed.xml")) == .skip("code or data file"))
        #expect(!Rules.isPicture(.svg) && Rules.isPicture(.png))
        #expect(!LookoutPictureDrop.isPictureFile(folder.url.appendingPathComponent("logo.svg")))
    }

    @Test func anRTFDPackageIsOneDocumentWhoseInsideIsNeverWalked() throws {
        try folder.write("Letter.rtfd/TXT.rtf", Data(#"{\rtf1\ansi Dear landlord}"#.utf8))
        try folder.write("Letter.rtfd/picture.png", Data(count: 64))
        try folder.write("Tool.app/Contents/readme.txt")
        let report = Crawler.crawl([folder.url], options: IndexOptions(), readsLastUsed: false, home: "/nonexistent")
        #expect(names(report) == ["Letter.rtfd"])
        let letter = try #require(report.candidates.first)
        #expect(letter.kind == .doc)
        // The size and date are the text's, so an edit in place reads as a change; the identity is the package's.
        var package = stat()
        #expect(lstat(letter.path, &package) == 0 && letter.inode == UInt64(package.st_ino))
        #expect(letter.size == Int64(#"{\rtf1\ansi Dear landlord}"#.utf8.count))
        #expect(report.skipped["app or bundle"] == 1)
    }

    @Test func anRTFDWithoutItsTextOrWithALinkedTextIsLeftOut() throws {
        try folder.folder("root/Empty.rtfd")
        let secret = try folder.write("outside/secret.rtf", Data("hunter2".utf8))
        try folder.folder("root/Linked.rtfd")
        try FileManager.default.createSymbolicLink(at: folder.url.appendingPathComponent("root/Linked.rtfd/TXT.rtf"),
                                                   withDestinationURL: secret)
        let report = Crawler.crawl([folder.url.appendingPathComponent("root")], options: IndexOptions(),
                                   readsLastUsed: false, home: "/nonexistent")
        #expect(report.candidates.isEmpty)
        #expect(report.skipped["link or special file"] == 2)
    }

    @Test func theWalkReportsWhatItHasFoundWhileItWalks() throws {
        for index in 0..<(Crawler.foundReportInterval * 2 + 3) { try folder.write("notes/\(index).txt") }
        var reports: [Int] = []
        let report = Crawler.crawl([folder.url], options: IndexOptions(), readsLastUsed: false, home: "/nonexistent") {
            reports.append($0)
        }
        #expect(reports == [Crawler.foundReportInterval, Crawler.foundReportInterval * 2])
        #expect(report.candidates.count == Crawler.foundReportInterval * 2 + 3)
    }

    // MARK: Reading

    private func gate(root: String) -> QueuedFileGate {
        QueuedFileGate(roots: [root], options: IndexOptions(), home: "/nonexistent")
    }

    private func record(_ path: String) throws -> FileRecord {
        var info = stat()
        try #require(lstat(path, &info) == 0)
        return FileRecord(id: 1, path: path, kind: .doc, size: 0, mtime: 0, inode: UInt64(info.st_ino), device: 1,
                          state: "pending", lastUsed: nil)
    }

    @Test func theGateReadsTheTextInsideAnRTFD() throws {
        try folder.write("root/Letter.rtfd/TXT.rtf", Data(#"{\rtf1\ansi Dear landlord}"#.utf8))
        let file = try record(folder.path + "/root/Letter.rtfd")
        guard case .read(let data) = gate(root: folder.path + "/root").open(file) else {
            Issue.record("not read")
            return
        }
        #expect(String(decoding: data, as: UTF8.self).contains("Dear landlord"))
    }

    @Test func theGateNeverFollowsALinkInsideOrInPlaceOfAnRTFD() throws {
        let secret = try folder.write("outside/secret.rtf", Data("hunter2".utf8))
        let text = try folder.write("root/Letter.rtfd/TXT.rtf", Data("{\\rtf1 hi}".utf8))
        let gate = gate(root: folder.path + "/root")
        let file = try record(folder.path + "/root/Letter.rtfd")
        try FileManager.default.removeItem(at: text)
        try FileManager.default.createSymbolicLink(at: text, withDestinationURL: secret)
        guard case .refused(let state, let detail) = gate.open(file) else {
            Issue.record("read through a linked TXT.rtf")
            return
        }
        #expect(state == "skipped" && detail == "link or special file")

        // The package itself swapped for a link to another package.
        try folder.write("outside/Other.rtfd/TXT.rtf", Data("hunter2".utf8))
        let package = folder.url.appendingPathComponent("root/Letter.rtfd")
        try FileManager.default.removeItem(at: package)
        try FileManager.default.createSymbolicLink(at: package,
                                                   withDestinationURL: folder.url.appendingPathComponent("outside/Other.rtfd"))
        guard case .refused(let linkedState, _) = gate.open(file) else {
            Issue.record("read through a linked package")
            return
        }
        #expect(linkedState == "skipped")
    }

    // MARK: Text

    @Test func subtitlesKeepOnlyWhatIsSaid() {
        let srt = """
            1
            00:00:01,000 --> 00:00:04,000
            <i>Welcome</i> to the
            harbour tour.

            2
            00:00:05,000 --> 00:00:07,500
            {\\an8}The lighthouse is 1902.
            """
        #expect(DocumentText.subtitles(srt) == "Welcome to the harbour tour.\nThe lighthouse is 1902.")
        let vtt = """
            WEBVTT - Tour

            NOTE written by hand

            STYLE
            ::cue { color: yellow }

            intro
            00:01.000 --> 00:04.000 position:10%
            <v Anna>Look &amp; listen</v>

            00:05.000 --> 00:06.000
            <c.loud>Gulls!</c>
            """
        #expect(DocumentText.subtitles(vtt) == "Look & listen\nGulls!")
    }

    @Test func latexKeepsItsWordsWithoutCommandsOrComments() {
        let tex = #"""
            \documentclass{article}
            \usepackage{graphicx}
            \begin{document}
            \section{Results} % TODO rewrite
            The tide rose by 12\% in \emph{one} night~\cite{harbour}.\\
            \includegraphics[width=3cm]{tide.png}
            \end{document}
            """#
        #expect(DocumentText.latex(tex) == "Results\nThe tide rose by 12% in one night .")
    }

    @Test func aWebArchiveIsReadThroughItsMainResource() throws {
        let page = Data("<html><head><title>x</title></head><body><p>Caf&eacute; <b>Sylt</b></p><script>x()</script></body></html>"
            .utf8)
        let archive: [String: Any] = ["WebMainResource": ["WebResourceData": page, "WebResourceMIMEType": "text/html",
                                                          "WebResourceTextEncodingName": "UTF-8",
                                                          "WebResourceURL": "https://example.com/"],
                                      "WebSubresources": [["WebResourceData": Data(count: 8)]]]
        let data = try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
        #expect(try DocumentText.text(of: data, fileExtension: "webarchive") == "Caf&eacute; Sylt")
        #expect(throws: DocumentText.Failure.self) { try DocumentText.webArchive(Data("not a plist".utf8)) }
        #expect(try DocumentText.text(of: Data("<p>Hi</p>".utf8), fileExtension: "xhtml") == "Hi")
        #expect(try DocumentText.text(of: Data("= Title".utf8), fileExtension: "adoc") == "= Title")
        #expect(try DocumentText.text(of: Data(), fileExtension: "rtfd") == nil)
    }

    // MARK: An existing index

    /// Ignored files were never recorded, so the new types arrive as new files on the next sync, and an SVG the old
    /// rules indexed (and failed) leaves the index. Nothing else is read again, so no rules version is needed.
    @Test func theNextSyncAddsNewTypesAndDropsSVGWithoutReadingAnythingAgain() throws {
        let root = try folder.folder("root")
        try folder.write("root/notes.txt")
        try folder.write("root/talk.srt")
        try folder.write("root/Letter.rtfd/TXT.rtf", Data("{\\rtf1 hi}".utf8))
        let logo = try folder.write("root/logo.svg")
        let store = try IndexStore(directory: folder.url.appendingPathComponent("index"))

        // What the old rules stored: the text file, read, and the SVG as a picture that failed.
        let old = Crawler.crawl([root], options: IndexOptions(), readsLastUsed: false, home: "/nonexistent")
        var before = old
        before.candidates = old.candidates.filter { $0.path.hasSuffix("notes.txt") }
        var info = stat()
        try #require(lstat(logo.path, &info) == 0)
        before.candidates.append(Candidate(path: logo.path, kind: .image, size: Int64(info.st_size), mtime: 0,
                                           inode: UInt64(info.st_ino), device: UInt64(bitPattern: Int64(info.st_dev))))
        try IndexSync.apply(before, roots: [root], to: store)
        let notes = try #require(try store.file(at: root.path + "/notes.txt"))
        try store.finish(notes.id, state: "done")
        try store.finish(try #require(try store.file(at: logo.path)).id, state: "failed", detail: "can't decode image")

        let summary = try IndexSync.apply(old, roots: [root], to: store)
        #expect(summary.added == 2 && summary.removed == 1 && summary.unchanged == 1 && summary.changed == 0)
        #expect(try store.file(at: logo.path) == nil)
        #expect(try store.file(at: root.path + "/notes.txt")?.state == "done")
        #expect(try store.file(at: root.path + "/Letter.rtfd")?.state == "pending")
        #expect(try store.file(at: root.path + "/talk.srt")?.state == "pending")
    }
}
