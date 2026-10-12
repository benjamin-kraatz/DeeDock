import Darwin
import Foundation
import Testing
@testable import DeeDock

/// The index database and the sync that keeps it in step with a crawl: what's queued, re-queued, moved, removed, and
/// in what order it's indexed. No model: vectors are written as the indexer would write them.
struct LookoutIndexStoreTests {
    private let folder = LookoutTestFolder()

    private func store() throws -> IndexStore {
        try IndexStore(directory: folder.url.appendingPathComponent("index"))
    }

    private func file(_ path: String, kind: FileKind = .image, size: Int64 = 10, mtime: Double = 1, inode: UInt64,
                      device: UInt64 = 1, lastUsed: Double? = nil) -> Candidate {
        Candidate(path: path, kind: kind, size: size, mtime: mtime, inode: inode, device: device, lastUsed: lastUsed)
    }

    private func crawl(_ candidates: [Candidate]) -> CrawlReport {
        var report = CrawlReport()
        report.candidates = candidates
        return report
    }

    private func count(_ store: IndexStore, _ sql: String) throws -> Int {
        var count = 0
        try store.db.query(sql) { count = Int($0.int(0)) }
        return count
    }

    private let vector = (0..<Vectors.dimension).map { Float($0 % 7) / 7 }

    @Test func aNewIndexIsSchemaOneWithFilesPending() throws {
        let store = try store()
        var version: Int64 = 0
        try store.db.query("PRAGMA user_version") { version = $0.int(0) }
        #expect(version == IndexStore.schemaVersion)
        #expect(IndexStore.schemaVersion == 1)
        let id = try store.insert(file("/a/x.png", inode: 1, lastUsed: 5))
        let record = try #require(try store.file(at: "/a/x.png"))
        #expect(record.id == id && record.state == "pending" && record.lastUsed == 5)
        #expect(try count(store, "SELECT COUNT(*) FROM fts") == 1)   // the name is searchable at once
    }

    @Test func anotherFileAtThePathIsQueuedAgainButARemountIsNot() throws {
        let store = try store()
        let roots = [URL(fileURLWithPath: "/a")]
        let first = try IndexSync.apply(crawl([file("/a/x.png", inode: 1)]), roots: roots, to: store)
        let id = try #require(first.queued.first)
        try store.addSegment(file: id, kind: .image, modality: .image, vector: vector)
        try store.finish(id, state: "done")
        // Remounted: a new device number, the same file.
        let remounted = try IndexSync.apply(crawl([file("/a/x.png", inode: 1, device: 7)]), roots: roots, to: store)
        #expect(remounted.unchanged == 1 && remounted.queued.isEmpty)
        #expect(try store.file(at: "/a/x.png")?.state == "done")
        // Replaced with contents of the same length, the date kept: another inode.
        let replaced = try IndexSync.apply(crawl([file("/a/x.png", inode: 2)]), roots: roots, to: store)
        #expect(replaced.changed == 1 && replaced.queued == [id] && replaced.vectorsChanged)
        let record = try #require(try store.file(at: "/a/x.png"))
        #expect(record.state == "pending" && record.inode == 2)
        #expect(try count(store, "SELECT COUNT(*) FROM segments WHERE kind != 'name'") == 0)
        // A move found by its inode still keeps the row.
        let moved = try IndexSync.apply(crawl([file("/a/renamed.png", inode: 2)]), roots: roots, to: store)
        #expect(moved.moved == 1 && moved.queued.isEmpty)
        #expect(try store.file(at: "/a/renamed.png")?.id == id)
    }

    @Test func aMoveThatChangesTheKindIsReadAgainAsTheNewKind() throws {
        let store = try store()
        let roots = [URL(fileURLWithPath: "/a")]
        let first = try IndexSync.apply(crawl([file("/a/capture.png", kind: .image, inode: 3)]), roots: roots, to: store)
        let id = try #require(first.queued.first)
        try store.addSegment(file: id, kind: .image, modality: .image, vector: vector)
        try store.finish(id, state: "done")
        let renamed = try IndexSync.apply(crawl([file("/a/Screenshot capture.png", kind: .screenshot, inode: 3)]),
                                          roots: roots, to: store)
        #expect(renamed.moved == 1 && renamed.added == 0 && renamed.removed == 0 && renamed.queued == [id])
        #expect(renamed.changed == 1 && renamed.vectorsChanged, "its segments went: the app reloads")
        let record = try #require(try store.file(at: "/a/Screenshot capture.png"))
        #expect(record.id == id && record.kind == .screenshot && record.state == "pending")
        #expect(try count(store, "SELECT COUNT(*) FROM segments WHERE kind != 'name'") == 0)
    }

    /// A drive gets a new device number at every mount. The sync after a remount records it for each unchanged file
    /// without reading it again, so a later rename is still a move and keeps the vectors.
    @Test func aRemountRefreshesTheDeviceAndALaterRenameKeepsTheVectors() throws {
        let store = try store()
        let roots = [URL(fileURLWithPath: "/a")]
        let id = try #require(try IndexSync.apply(crawl([file("/a/scan.png", inode: 5, device: 1)]), roots: roots,
                                                  to: store).queued.first)
        try store.addSegment(file: id, kind: .image, modality: .image, vector: vector)
        try store.finish(id, state: "done")
        let remounted = try IndexSync.apply(crawl([file("/a/scan.png", inode: 5, device: 9)]), roots: roots, to: store)
        #expect(remounted.unchanged == 1 && remounted.queued.isEmpty && !remounted.vectorsChanged)
        #expect(try store.file(at: "/a/scan.png")?.device == 9 && store.file(at: "/a/scan.png")?.state == "done")
        let renamed = try IndexSync.apply(crawl([file("/a/scan 2.png", inode: 5, device: 9)]), roots: roots, to: store)
        #expect(renamed.moved == 1 && renamed.added == 0 && renamed.removed == 0 && renamed.queued.isEmpty)
        #expect(!renamed.vectorsChanged)
        #expect(try store.file(at: "/a/scan 2.png")?.id == id)
        #expect(try count(store, "SELECT COUNT(*) FROM segments WHERE kind != 'name'") == 1, "vectors kept")
    }

    /// A volume mounted inside a root numbers its inodes on its own. A file there that goes, and a new file on the
    /// root's volume with the same inode, size, date and kind, are two files: the new one is read, never handed the
    /// old one's contents. The root here is a real folder, so its device is the one the candidates carry.
    @Test func aFileOnANestedVolumeIsNeverTakenForAnotherVolumesFile() throws {
        let store = try store()
        let roots = [folder.url]
        var info = stat()
        try #require(stat(folder.path, &info) == 0)
        let rootDevice = UInt64(bitPattern: Int64(info.st_dev))
        let nested = file(folder.path + "/Mounted/photo.png", inode: 42, device: rootDevice &+ 1)
        let id = try #require(try IndexSync.apply(crawl([nested]), roots: roots, to: store).queued.first)
        try store.addSegment(file: id, kind: .image, modality: .image, vector: vector)
        try store.finish(id, state: "done")
        let newFile = file(folder.path + "/photo.png", inode: 42, device: rootDevice)
        let summary = try IndexSync.apply(crawl([newFile]), roots: roots, to: store)
        #expect(summary.moved == 0 && summary.added == 1 && summary.removed == 1 && summary.vectorsChanged)
        let record = try #require(try store.file(at: folder.path + "/photo.png"))
        #expect(record.id != id && record.state == "pending")
        #expect(try count(store, "SELECT COUNT(*) FROM segments WHERE kind != 'name'") == 0)
    }

    @Test func aChangedFileIsQueuedAgainWithoutItsOldSegments() throws {
        let store = try store()
        let roots = [URL(fileURLWithPath: "/a")]
        let first = try IndexSync.apply(crawl([file("/a/x.png", inode: 1)]), roots: roots, to: store)
        let id = try #require(first.queued.first)
        try store.addSegment(file: id, kind: .image, modality: .image, vector: vector)
        try store.finish(id, state: "done")
        let unchanged = try IndexSync.apply(crawl([file("/a/x.png", inode: 1)]), roots: roots, to: store)
        #expect(unchanged.unchanged == 1 && unchanged.queued.isEmpty)
        let changed = try IndexSync.apply(crawl([file("/a/x.png", size: 20, mtime: 2, inode: 1)]), roots: roots,
                                          to: store)
        #expect(changed.changed == 1 && changed.queued == [id])
        #expect(try store.file(at: "/a/x.png")?.state == "pending")
        #expect(try count(store, "SELECT COUNT(*) FROM segments WHERE kind != 'name'") == 0)
        #expect(try count(store, "SELECT COUNT(*) FROM segments WHERE kind = 'name'") == 1)
    }

    @Test func aMoveKeepsItsVectorsAndIsNotEmbeddedAgain() throws {
        let store = try store()
        let roots = [URL(fileURLWithPath: "/a")]
        let id = try #require(try IndexSync.apply(crawl([file("/a/Screenshot.png", inode: 7)]), roots: roots,
                                                  to: store).queued.first)
        try store.addSegment(file: id, kind: .image, modality: .image, vector: vector)
        try store.finish(id, state: "done")
        let moved = try IndexSync.apply(crawl([file("/a/project/Screenshot renamed.png", inode: 7)]), roots: roots,
                                        to: store)
        #expect(moved.moved == 1 && moved.removed == 0 && moved.added == 0 && moved.queued.isEmpty)
        let record = try #require(try store.file(at: "/a/project/Screenshot renamed.png"))
        #expect(record.id == id && record.state == "done")
        #expect(try store.file(at: "/a/Screenshot.png") == nil)
        #expect(try store.counts().vectors == 1)
        var name = ""
        try store.db.query("SELECT name FROM fts WHERE rowid IN (SELECT id FROM segments WHERE kind = 'name')") {
            name = $0.text(0) ?? ""
        }
        #expect(name == "Screenshot renamed.png")   // keyword search finds it under its new name
    }

    @Test func aDeletedFileLeavesButAVanishedRootKeepsItsFiles() throws {
        let store = try store()
        let drive = try folder.folder("drive")
        try IndexSync.apply(crawl([file(drive.path + "/a.png", inode: 1), file(drive.path + "/b.png", inode: 2)]),
                            roots: [drive], to: store)
        let gone = try IndexSync.apply(crawl([file(drive.path + "/a.png", inode: 1)]), roots: [drive], to: store)
        #expect(gone.removed == 1)
        try FileManager.default.removeItem(at: drive)   // ejected: it looks empty, but nothing was deleted
        let ejected = try IndexSync.apply(crawl([]), roots: [drive], to: store)
        #expect(ejected.removed == 0)
        #expect(try store.files(under: [drive.path]).count == 1)
    }

    @Test func pruneKeepsOnlyChosenFolders() throws {
        let store = try store()
        try store.insert(file("/a/x.png", inode: 1))
        try store.insert(file("/a/sub/y.png", inode: 2))
        try store.insert(file("/ab/z.png", inode: 3))   // a sibling whose name starts like "/a", not inside it
        try store.insert(file("/b/w.png", inode: 4))
        #expect(try store.prune(keepingUnder: ["/a"]) == 2)
        #expect(try store.files(under: ["/a"]).count == 2)
        #expect(try store.files(under: ["/ab", "/b"]).isEmpty)
        #expect(try count(store, "SELECT COUNT(*) FROM fts") == 2)   // the pruned files' names left keyword search too
    }

    @Test func theMostRecentlyUsedFilesAreIndexedFirst() throws {
        let store = try store()
        var files = [
            file("/a/old-photo.png", mtime: 100, inode: 1),
            file("/a/opened-yesterday.pdf", kind: .pdf, mtime: 50, inode: 2, lastUsed: 300),
            file("/a/new-doc.txt", kind: .doc, mtime: 200, inode: 3),
            file("/a/same-time-shot.png", kind: .screenshot, mtime: 200, inode: 4),
        ]
        let roots = [URL(fileURLWithPath: "/a")]
        try IndexSync.apply(crawl(files), roots: roots, to: store)
        // Last used, else modified, newest first; at the same time, screenshots before documents.
        #expect(try store.pending(limit: nil).map(\.path)
                == ["/a/opened-yesterday.pdf", "/a/same-time-shot.png", "/a/new-doc.txt", "/a/old-photo.png"])
        #expect(try store.pending(limit: 1).map(\.path) == ["/a/opened-yesterday.pdf"])
        // Opened since the last sync: a file that didn't change moves up the queue.
        files[0].lastUsed = 400
        let summary = try IndexSync.apply(crawl(files), roots: roots, to: store)
        #expect(summary.unchanged == 4 && summary.queued.isEmpty)
        #expect(try store.pending(limit: 1).map(\.path) == ["/a/old-photo.png"])
    }

    @Test func scopeLimitsWhatIsWaiting() throws {
        let store = try store()
        try store.insert(file("/a/x.png", inode: 1))
        try store.insert(file("/drive/y.png", inode: 2))   // on a drive that's unplugged
        store.scope = ["/a"]
        #expect(try store.pendingCount() == 1)
        #expect(try store.pending(limit: nil).map(\.path) == ["/a/x.png"])
        #expect(try store.counts().byKindAndState["image"]?["pending"] == 1)
        store.scope = []
        #expect(try store.pendingCount() == 0)
        store.scope = nil
        #expect(try store.pendingCount() == 2)
    }

    @Test func theAppReadsWhileTheServiceWrites() throws {
        let index = folder.url.appendingPathComponent("index")
        #expect(try IndexStore.openReadOnly(directory: index) == nil)
        #expect(!FileManager.default.fileExists(atPath: index.path))   // reading creates nothing
        let writer = try IndexStore(directory: index)
        try writer.insert(file("/a/x.png", inode: 1))
        let reader = try #require(try IndexStore.openReadOnly(directory: index))
        #expect(try reader.pendingCount() == 1)
        #expect(throws: (any Error).self) { try reader.insert(file("/a/y.png", inode: 2)) }
        try writer.insert(file("/a/z.png", inode: 3))
        #expect(try reader.pendingCount() == 2)   // WAL: the reader sees the writer's commits
    }

    @Test func aResetQueuesEverythingAndKeepsNames() throws {
        let store = try store()
        let id = try store.insert(file("/a/x.png", inode: 1))
        try store.addSegment(file: id, kind: .image, modality: .image, vector: vector)
        try store.finish(id, state: "done")
        try store.setMeta("fingerprint", "old model")
        try store.resetAll()
        #expect(try store.meta("fingerprint") == nil)
        #expect(try store.pendingCount() == 1)
        #expect(try store.counts().vectors == 0)
        #expect(try count(store, "SELECT COUNT(*) FROM fts") == 1)
    }
}
