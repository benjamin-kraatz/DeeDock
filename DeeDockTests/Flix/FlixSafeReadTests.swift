import Foundation
import Testing
@testable import DeeDock

/// Background reads cannot reach a protected folder through another spelling of its name or
/// through a link, and they re-check the policy at the moment they open the file. Uses a temporary
/// folder that stands in for the home folder; nothing outside it is touched.
@Suite(.serialized)
struct FlixSafeReadTests {
    private func makeHome() throws -> URL {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "FlixSafeRead-\(UUID().uuidString)", directoryHint: .isDirectory)
        for folder in ["Documents", "Projects"] {
            try FileManager.default.createDirectory(at: base.appending(path: folder), withIntermediateDirectories: true)
        }
        try Data("secret".utf8).write(to: base.appending(path: "Documents/tax.txt"))
        try Data("code".utf8).write(to: base.appending(path: "Projects/main.swift"))
        return base
    }

    @Test func otherSpellingsOfAProtectedFolderAreProtected() {
        let policy = FlixReadPolicy(home: "/Users/someone", allowedRoots: [])
        #expect(policy.isProtected("/Users/someone/Documents/tax.pdf"))
        #expect(policy.isProtected("/Users/someone/documents/tax.pdf"))
        #expect(policy.isProtected("/Users/someone/DOWNLOADS/file.zip"))
        #expect(policy.isProtected("/users/SOMEONE/Desktop/a.png"))
        #expect(policy.isProtected("/volumes/Backup/a.txt"))
        #expect(!policy.canRead("/Users/someone/dOcUmEnTs/tax.pdf"))
        #expect(!policy.isProtected("/Users/someone/Projects/main.swift"))
        #expect(FlixPaths.folded("Re\u{0301}sume\u{0301}") == FlixPaths.folded("RÉSUMÉ"))
    }

    @Test func anAllowedFolderMatchesWhateverItsSpelling() {
        let policy = FlixReadPolicy(home: "/Users/someone", allowedRoots: ["/Users/someone/Documents/Work"])
        #expect(policy.canRead("/Users/someone/documents/work/plan.pdf"))
        #expect(!policy.canRead("/Users/someone/documents/tax.pdf"))
    }

    @Test func aSafeFileReadsWhatThePolicyChecked() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let policy = FlixReadPolicy(home: home.path, allowedRoots: [])
        let file = try #require(FlixSafeFile.open(home.appending(path: "Projects/main.swift").path, policy: policy))
        #expect(String(decoding: file.read(upTo: 100), as: UTF8.self) == "code")
        #expect(file.mapped(maximumBytes: 100) == Data("code".utf8))
        #expect(file.mapped(maximumBytes: 2) == nil)
        // A protected file is never opened, by any spelling.
        #expect(FlixSafeFile.open(home.appending(path: "Documents/tax.txt").path, policy: policy) == nil)
        #expect(FlixSafeFile.open(home.appending(path: "documents/tax.txt").path, policy: policy) == nil)
    }

    @Test func aLinkSwappedInAfterQueueingIsNotFollowed() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let policy = FlixReadPolicy(home: home.path, allowedRoots: [])
        let queued = home.appending(path: "Projects/report.txt")
        try Data("report".utf8).write(to: queued)
        #expect(policy.canRead(queued.path))
        // After the item was queued, its file became a link into Documents.
        try FileManager.default.removeItem(at: queued)
        try FileManager.default.createSymbolicLink(at: queued, withDestinationURL: home.appending(path: "Documents/tax.txt"))
        #expect(FlixSafeFile.open(queued.path, policy: policy) == nil)
        #expect(policy.readableURL(queued.path) == nil)
        // Likewise when a folder on the way became one.
        let folder = home.appending(path: "Projects/Inbox", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: home.appending(path: "Documents"))
        #expect(FlixSafeFile.open(folder.appending(path: "tax.txt").path, policy: policy) == nil)
    }

    @Test func linksWithinReadableFoldersResolveToTheirTarget() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let policy = FlixReadPolicy(home: home.path, allowedRoots: [])
        let link = home.appending(path: "Projects/alias.swift")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home.appending(path: "Projects/main.swift"))
        #expect(policy.readableURL(link.path)?.path == home.appending(path: "Projects/main.swift").path)
        let file = try #require(FlixSafeFile.open(link.path, policy: policy))
        #expect(file.path == home.appending(path: "Projects/main.swift").path)
    }

    @Test func specialFilesAreNeverRead() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let fifo = home.appending(path: "Projects/pipe").path
        #expect(mkfifo(fifo, 0o600) == 0)
        #expect(FlixSafeFile.open(fifo, policy: FlixReadPolicy(home: home.path, allowedRoots: [])) == nil)
    }
}
