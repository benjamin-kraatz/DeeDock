import Darwin
import Foundation
import Testing
@testable import DeeDock

/// The check just before a queued file is read (`QueuedFileGate`): what changed on disk since the crawl queued it.
struct LookoutQueuedFileGateTests {
    private let folder = LookoutTestFolder()
    private var root: String { folder.path + "/root" }

    private func gate(_ options: IndexOptions = IndexOptions()) -> QueuedFileGate {
        QueuedFileGate(roots: [root], options: options, home: folder.path)
    }

    /// The row the crawl would have stored for the file at `relative` (under the root) as it is now.
    private func queued(_ relative: String, kind: FileKind = .doc) throws -> FileRecord {
        let path = root + "/" + relative
        var info = stat()
        try #require(lstat(path, &info) == 0)
        return record(path, kind: kind, inode: UInt64(info.st_ino))
    }

    private func record(_ path: String, kind: FileKind = .doc, inode: UInt64 = 1) -> FileRecord {
        FileRecord(id: 1, path: path, kind: kind, size: 0, mtime: 0, inode: inode, device: 1, state: "pending",
                   lastUsed: nil)
    }

    @Test func aQueuedFileIsReadFromTheDescriptorThatWasChecked() throws {
        try folder.write("root/notes.txt", Data("trip to Sylt".utf8))
        guard case .read(let data) = gate().open(try queued("notes.txt")) else {
            Issue.record("not read")
            return
        }
        #expect(String(decoding: data, as: UTF8.self) == "trip to Sylt")
    }

    @Test func aFileReplacedByALinkIsNeverFollowed() throws {
        let secret = try folder.write("outside/credentials-copy.txt", Data("hunter2".utf8))
        let notes = try folder.write("root/notes.txt")
        let file = try queued("notes.txt")
        try FileManager.default.removeItem(at: notes)
        try FileManager.default.createSymbolicLink(at: notes, withDestinationURL: secret)
        guard case .refused(let state, let detail) = gate().open(file) else {
            Issue.record("the link was read")
            return
        }
        #expect(state == "skipped" && detail == "link or special file")
    }

    @Test func aFolderOnTheWayReplacedByALinkIsRefused() throws {
        try folder.write("outside/notes.txt", Data("hunter2".utf8))
        let subfolder = try folder.write("root/sub/notes.txt").deletingLastPathComponent()
        let file = try queued("sub/notes.txt")
        try FileManager.default.removeItem(at: subfolder)
        try FileManager.default.createSymbolicLink(at: subfolder, withDestinationURL: folder.url.appendingPathComponent("outside"))
        guard case .refused(let state, _) = gate().open(file) else {
            Issue.record("read through the linked folder")
            return
        }
        #expect(state == "skipped")
    }

    @Test func anotherFileAtThePathIsQueuedAgain() throws {
        let notes = try folder.write("root/notes.txt", Data("old".utf8))
        let file = try queued("notes.txt")
        // Saved the way editors save: a new file renamed over the old one, so both exist and the inode differs.
        let replacement = try folder.write("root/notes.new", Data("newer text".utf8))
        #expect(rename(replacement.path, notes.path) == 0)
        guard case .changed(let now) = gate().open(file) else {
            Issue.record("not queued again")
            return
        }
        #expect(now.path == file.path && now.inode != file.inode && now.size == 10 && now.kind == .doc)
    }

    @Test func fifosAndMissingFilesAreNotRead() throws {
        try folder.folder("root")
        #expect(mkfifo(root + "/pipe.txt", 0o600) == 0)
        guard case .refused(let state, _) = gate().open(record(root + "/pipe.txt")) else {
            Issue.record("a FIFO was opened")
            return
        }
        #expect(state == "skipped")
        guard case .refused(let missing, _) = gate().open(record(root + "/gone.txt")) else {
            Issue.record("a missing file was read")
            return
        }
        #expect(missing == "failed")
    }

    @Test("The settings and the crawl's folder rules are checked again on the stored path", arguments: [
        ("credentials.txt", "key or password file"),
        ("notes.md", "excluded type"),
        ("Media/clip-notes.txt", "excluded folder"),
        ("code/.git/notes.txt", "hidden folder"),
        ("code/node_modules/pkg/readme.txt", "developer folder"),
    ])
    func settingsAreCheckedAgain(relative: String, reason: String) {
        var options = IndexOptions()
        options.excludedExtensions = ["md"]
        options.excludedFolders = [root + "/Media"]
        #expect(gate(options).refusal(forPath: root + "/" + relative) == reason)
    }

    @Test func aFileOutsideTheRootsOrInLibraryIsRefused() {
        #expect(gate().refusal(forPath: folder.path + "/elsewhere/notes.txt") == "outside the chosen folders")
        #expect(gate().refusal(forPath: root + "/notes.txt") == nil)
        // A folder chosen inside a skipped one is read whole.
        var options = IndexOptions()
        options.excludedFolders = [root + "/Media"]
        let nested = QueuedFileGate(roots: [root, root + "/Media/Courses"], options: options, home: folder.path)
        #expect(nested.refusal(forPath: root + "/Media/Courses/syllabus.txt") == nil)
        #expect(nested.refusal(forPath: root + "/Media/movie.txt") == "excluded folder")
        // ~/Library on the way down from a root (the home folder itself never is one; this guards the rule).
        let home = QueuedFileGate(roots: [folder.path], options: IndexOptions(), home: folder.path)
        #expect(home.refusal(forPath: folder.path + "/Library/Mail/message.txt") == "~/Library")
    }

    /// A sparse file of `size` bytes at `relative` under the root, ending in "end" (nothing that size is written).
    @discardableResult
    private func sparse(_ relative: String, size: Int) throws -> URL {
        let url = try folder.write("root/" + relative, Data())
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.seek(toOffset: UInt64(size - 3))
        try handle.write(contentsOf: Data("end".utf8))
        try handle.close()
        return url
    }

    @Test func aFileOverTheReadLimitIsSkipped() throws {
        try sparse("book.pdf", size: QueuedFileGate.maxReadBytes + 1)
        guard case .refused(let state, let detail) = gate().open(try queued("book.pdf", kind: .pdf)) else {
            Issue.record("read past the limit")
            return
        }
        #expect(state == "skipped" && detail.hasPrefix("too large to read"))
    }

    /// The race itself can't be timed in a test, so this sets up the state it leaves: `fstat` said 20 MB, and the file
    /// is cut to 9 MB before the read, past the first 8 MB piece. Reading stops at the new end instead of faulting,
    /// which a memory-mapped read would do (SIGBUS) once it touched the missing pages.
    @Test func aFileCutShorterWhileItsReadYieldsWhatsLeft() throws {
        let size = 20 << 20
        let url = try sparse("book.pdf", size: size)
        let descriptor = open(url.path, O_RDONLY)
        try #require(descriptor >= 0)
        defer { close(descriptor) }
        let writer = try FileHandle(forWritingTo: url)
        try writer.truncate(atOffset: UInt64(9 << 20))
        try writer.close()
        let data = try QueuedFileGate.contents(of: descriptor, size: size)
        #expect(data.count == 9 << 20)

        let whole = try queued("book.pdf", kind: .pdf)
        guard case .read(let read) = gate().open(whole) else {
            Issue.record("not read")
            return
        }
        #expect(read.count == 9 << 20)
    }

    /// Where the kernel says the open file is (`F_GETPATH`), against the row. Paths aren't compared by spelling: on a
    /// case-sensitive volume `Notes` linked to its sibling `NOTES` differs only in case and is another file.
    @Test func anotherOpenPathMustPassTheRulesAndBeTheQueuedFile() {
        let file = record(root + "/Notes/x.txt", inode: 5)
        let gate = gate()
        #expect(gate.placeRefusal(opened: file.path, file: file, inode: 5) == nil)
        #expect(gate.placeRefusal(opened: root + "/NOTES/x.txt", file: file, inode: 9) != nil, "a case-twin sibling")
        #expect(gate.placeRefusal(opened: root + "/NOTES/x.txt", file: file, inode: 5) == nil, "a case-only rename")
        #expect(gate.placeRefusal(opened: folder.path + "/elsewhere/x.txt", file: file, inode: 5)
            == "outside the chosen folders")
        #expect(gate.placeRefusal(opened: root + "/.private/x.txt", file: file, inode: 5) == "hidden folder")
    }
}
