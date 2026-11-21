import Foundation
import Testing
@testable import DeeDock

/// Destructive commands act only on the file a row lists: a file replaced at the same path, or a
/// row that has not recorded its file yet, is left alone and reported, and the history keeps each
/// row's identity current. Uses a temporary folder; nothing outside it is touched.
@Suite(.serialized)
struct FlixFileCommandSafetyTests {
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "FlixCommandSafety-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "Archive"), withIntermediateDirectories: true)
        return folder
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    private func row(_ url: URL, identity: FlixFileIdentity?) -> FlixItem {
        FlixItem(path: url.path, name: url.lastPathComponent, kind: .document, activity: .opened, date: .now,
                 fileIdentity: identity)
    }

    /// Deletes `url` and writes a different file in its place, as a download with the same name would.
    private func replace(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
        try write("someone else's file", to: url)
    }

    @Test func aMoveLeavesAReplacedFileAlone() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Invoice.pdf")
        try write("invoice", to: url)
        let listed = row(url, identity: FlixFileIdentity.of(url))
        try replace(url)

        let report = FlixFileOperations.move([listed], into: folder.appending(path: "Archive"))
        #expect(report.moved.isEmpty)
        let stale = try #require(report.stale.first)
        #expect(stale.item.id == listed.id && !stale.wasUnchecked)
        // What is there now, so the row can be refreshed and the next attempt acts on it.
        #expect(stale.current == FlixFileIdentity.of(url))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "Archive/Invoice.pdf").path))
    }

    @Test func aRowWithoutAnIdentityIsCheckedBeforeAnythingHappens() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Notes.txt")
        try write("notes", to: url)
        let unchecked = row(url, identity: nil)

        let report = FlixFileOperations.move([unchecked], into: folder.appending(path: "Archive"))
        #expect(report.moved.isEmpty)
        #expect(report.stale.first?.wasUnchecked == true)
        #expect(report.stale.first?.current == FlixFileIdentity.of(url))
        // With the identity stored, the second attempt goes ahead.
        let refreshed = row(url, identity: report.stale.first?.current)
        #expect(FlixFileOperations.move([refreshed], into: folder.appending(path: "Archive")).moved.count == 1)
    }

    @Test func renameAndTrashRefuseAChangedFile() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Report.pdf")
        try write("v1", to: url)
        let listed = row(url, identity: FlixFileIdentity.of(url))
        try replace(url)

        guard case .stale = FlixFileOperations.rename(listed, to: "Renamed.pdf") else {
            Issue.record("a replaced file was renamed")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "Renamed.pdf").path))

        let other = folder.appending(path: "Other.pdf")
        try write("other", to: other)
        let split = FlixFileOperations.trashable([listed, row(other, identity: FlixFileIdentity.of(other))])
        #expect(split.ready.map(\.path) == [other.path])
        #expect(split.stale.map(\.item.id) == [listed.id])
    }

    @Test func tidyChecksOnceAndUndoesInOneStep() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "scan 0001.pdf")
        try write("scan", to: url)
        let listed = row(url, identity: FlixFileIdentity.of(url))
        let archive = folder.appending(path: "Archive").path

        let outcome = FlixFileOperations.tidy(listed, rename: "Lease.pdf", moveTo: archive)
        #expect(outcome.renamed != nil && outcome.moved != nil && outcome.stale == nil)
        let undo = try #require(outcome.undo)
        #expect(undo.from.path == url.path && undo.to.path == archive + "/Lease.pdf")
        #expect(FlixFileOperations.moveBack([undo]).restored.count == 1)
        #expect(FileManager.default.fileExists(atPath: url.path))

        // A replaced file is neither renamed nor moved.
        try replace(url)
        let refused = FlixFileOperations.tidy(listed, rename: "Lease.pdf", moveTo: archive)
        #expect(refused.stale != nil && refused.renamed == nil && refused.moved == nil && refused.undo == nil)
    }

    @Test func identitiesAreReadOnlyWhereThePolicyAllows() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let documents = folder.appending(path: "Documents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try write("tax", to: documents.appending(path: "tax.pdf"))
        try write("free", to: folder.appending(path: "free.txt"))
        let policy = FlixReadPolicy(home: folder.path, allowedRoots: [])
        let found = FlixFileOperations.identities(of: [documents.appending(path: "tax.pdf").path,
                                                       folder.appending(path: "free.txt").path], policy: policy)
        #expect(found.keys.sorted() == [folder.appending(path: "free.txt").path])
    }

    // MARK: History

    @Test func theHistoryKeepsEachRowsIdentityCurrent() {
        let first = FlixFileIdentity(device: 1, inode: 10, isDirectory: false, size: 3, modified: 100)
        let second = FlixFileIdentity(device: 1, inode: 11, isDirectory: false, size: 4, modified: 200)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var document = FlixHistoryDocument()
        document.record(FlixActivityEvent(path: "/w/a.pdf", name: "a.pdf", kind: .document, activity: .created,
                                          date: t0, fileIdentity: first))
        #expect(document.items[0].fileIdentity == first)
        // An older event only fills in; it never replaces what the row recorded.
        document.record(FlixActivityEvent(path: "/w/a.pdf", name: "a.pdf", kind: .document, activity: .opened,
                                          date: t0.addingTimeInterval(-10), fileIdentity: second))
        #expect(document.items[0].fileIdentity == first)
        // A newer event without one (Spotlight) clears it, so the background pass reads the file anew.
        document.record(FlixActivityEvent(path: "/w/a.pdf", name: "a.pdf", kind: .document, activity: .opened,
                                          date: t0.addingTimeInterval(10)))
        #expect(document.items[0].fileIdentity == nil)
        let id = document.items[0].id
        // A capture for a path the row has left is ignored.
        let ignored = document.setIdentity(second, for: id, path: "/w/old.pdf")
        #expect(!ignored)
        let stored = document.setIdentity(second, for: id, path: "/w/a.pdf")
        #expect(stored)
        #expect(document.items[0].fileIdentity == second)
        document.relocate(id, to: "/w/b.pdf", name: "b.pdf", identity: first)
        #expect(document.items[0].path == "/w/b.pdf" && document.items[0].fileIdentity == first)
    }

    @Test func identitiesSurviveARoundTrip() throws {
        var document = FlixHistoryDocument()
        let identity = FlixFileIdentity(device: 7, inode: 42, isDirectory: true, size: nil, modified: nil)
        document.record(FlixActivityEvent(path: "/w/Folder", name: "Folder", kind: .folder, activity: .created,
                                          date: .now, fileIdentity: identity))
        let decoded = try JSONDecoder().decode(FlixHistoryDocument.self, from: JSONEncoder().encode(document))
        #expect(decoded.items[0].fileIdentity == identity)
    }

    // MARK: Worker

    @Test @MainActor func theWorkerRunsCommandsOffTheMainThread() async {
        let worker = FlixFileWorker()
        let ranOnMain = await worker.run { Thread.isMainThread }
        #expect(!ranOnMain)
        #expect(await worker.run { 41 + 1 } == 42)
    }
}
