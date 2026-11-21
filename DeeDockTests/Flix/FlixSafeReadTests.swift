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
        #expect(try file.contents(maximumBytes: 100) == Data("code".utf8))
        #expect(throws: FlixSafeFile.ReadError.tooLarge) { try file.contents(maximumBytes: 2) }
        // A protected file is never opened, by any spelling.
        #expect(FlixSafeFile.open(home.appending(path: "Documents/tax.txt").path, policy: policy) == nil)
        #expect(FlixSafeFile.open(home.appending(path: "documents/tax.txt").path, policy: policy) == nil)
    }

    /// Bytes are copied, never mapped: a file cut short while it is read is an error the reader
    /// handles, where a mapping would have crashed the app with `SIGBUS` on the missing pages.
    @Test func aFileTruncatedAfterOpeningIsAnErrorNotACrash() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let policy = FlixReadPolicy(home: home.path, allowedRoots: [])
        let url = home.appending(path: "Projects/big.bin")
        try Data(repeating: 7, count: 64 * 1_024).write(to: url)
        let file = try #require(FlixSafeFile.open(url.path, policy: policy))
        #expect(file.size == 64 * 1_024)
        // Rewritten in place, shorter, after the reader opened it.
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 1_000)
        try handle.close()
        #expect(throws: FlixSafeFile.ReadError.truncated) { try file.contents(maximumBytes: 1_000_000) }
        #expect(file.read(upTo: 64 * 1_024).count == 1_000)
        // An empty file and a folder have no contents to decode.
        let empty = home.appending(path: "Projects/empty.txt")
        try Data().write(to: empty)
        let opened = try #require(FlixSafeFile.open(empty.path, policy: policy))
        #expect(throws: FlixSafeFile.ReadError.empty) { try opened.contents(maximumBytes: 10) }
        let folder = try #require(FlixSafeFile.open(home.appending(path: "Projects").path, policy: policy))
        #expect(throws: FlixSafeFile.ReadError.directory) { try folder.contents(maximumBytes: 10) }
    }

    /// Rows name their folder without reading it, so a share that went away cannot stall drawing.
    @Test func folderNamesComeFromThePathAlone() {
        #expect(FlixFolderNames.displayName(of: "/Volumes/Gone Share/Invoices/") == "Invoices")
        let item = FlixItem(path: "/Volumes/Gone Share/Invoices/March.pdf", name: "March.pdf", kind: .document,
                            activity: .opened, date: .now)
        #expect(item.folderName == "Invoices")
    }

    /// The sensitive guard queues from memory: a path whose spelling is protected is never queued,
    /// so its check never reaches the disk.
    @MainActor @Test func theSensitiveGuardSkipsProtectedSpellingsWithoutTouchingThem() async throws {
        let sensitive = FlixSensitiveGuard(folder: nil)
        sensitive.setEnabled(true)
        let protected = FlixItem(path: "/FlixGuardHome/Documents/server.pem", name: "server.pem", kind: .document,
                                 activity: .downloaded, date: .now)
        sensitive.update(items: [protected], policy: FlixReadPolicy(home: "/FlixGuardHome", allowedRoots: []))
        try await Task.sleep(for: .milliseconds(100))
        #expect(sensitive.verdict(for: protected) == nil)
    }

    @Test func aLargeFileIsReadWholeInChunks() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let policy = FlixReadPolicy(home: home.path, allowedRoots: [])
        let url = home.appending(path: "Projects/chunks.bin")
        let bytes = Data((0..<(FlixSafeFile.chunkBytes * 2 + 123)).map { UInt8(truncatingIfNeeded: $0) })
        try bytes.write(to: url)
        let file = try #require(FlixSafeFile.open(url.path, policy: policy))
        #expect(try file.contents(maximumBytes: Int64(bytes.count)) == bytes)
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
        let target = home.appending(path: "Projects/main.swift")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        // The resolver returns the real path (`/private/var/…`), which `resolvingSymlinksInPath()`
        // in `makeHome` deliberately shortens back to `/var/…`; compare against `realpath`.
        let expected = try #require(realpath(target.path, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        })
        #expect(policy.readableURL(link.path)?.path == expected)
        let file = try #require(FlixSafeFile.open(link.path, policy: policy))
        #expect(file.path == expected)
    }

    @Test func specialFilesAreNeverRead() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let fifo = home.appending(path: "Projects/pipe").path
        #expect(mkfifo(fifo, 0o600) == 0)
        #expect(FlixSafeFile.open(fifo, policy: FlixReadPolicy(home: home.path, allowedRoots: [])) == nil)
    }
}
