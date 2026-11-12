import Foundation
import Testing
@testable import DeeDock

/// Staging, undo, removal and launch recovery, only inside fresh temporary directories.
struct VaporDeletionEngineTests {
    private struct Fixture {
        let temp: VaporTempDirectory
        let staging: URL
        let ledger: VaporLedgerFile
        let engine: VaporDeletionEngine

        init(stagingPath: String = "Caches/DOKK/Vapor/staging") throws {
            temp = try VaporTempDirectory("vapor-engine")
            staging = temp.url.appendingPathComponent(stagingPath, isDirectory: true)
            ledger = VaporLedgerFile(url: temp.url.appendingPathComponent("Support/ledger.json"))
            engine = VaporDeletionEngine(ledger: ledger, location: VaporStagingLocation(homeStaging: staging))
        }

        func cache(_ path: String, files: Int = 3) throws -> URL {
            let folder = try temp.folder(path)
            for index in 0..<files { try temp.file("\(path)/pkg\(index)/index.js", bytes: 64) }
            return folder
        }
    }

    @Test func stagingMovesTheFolderIntoStagingAndRecordsIt() async throws {
        let fixture = try Fixture()
        let folder = try fixture.cache("app/node_modules")
        let id = UUID()
        let outcomes = await fixture.engine.stage([VaporStageRequest(folderID: id, url: folder, bytes: 4096)])
        guard case .staged(let folderID, let entry) = outcomes.first else {
            Issue.record("expected staged, got \(outcomes)")
            return
        }
        #expect(folderID == id)
        #expect(!fixture.temp.exists(folder))
        #expect(fixture.temp.exists(entry.stagedURL))
        #expect(entry.stagedURL.deletingLastPathComponent().standardizedFileURL.path == fixture.staging.standardizedFileURL.path)
        #expect(entry.originalPath == folder.path)
        #expect(entry.bytes == 4096)
        #expect(fixture.ledger.read() == [entry])
        #expect(entry.state == .staged)
    }

    @Test func undoRenamesBackAndClearsTheLedger() async throws {
        let fixture = try Fixture()
        let folder = try fixture.cache("app/.next")
        let outcomes = await fixture.engine.stage([VaporStageRequest(folderID: UUID(), url: folder, bytes: 0)])
        guard case .staged(_, let entry) = outcomes.first else { Issue.record("not staged"); return }
        let restored = await fixture.engine.restore([entry])
        #expect(restored == [.restored(entry)])
        #expect(fixture.temp.exists(folder.appendingPathComponent("pkg0/index.js")))
        #expect(!fixture.temp.exists(entry.stagedURL))
        #expect(fixture.ledger.read().isEmpty)
    }

    @Test func undoNeverOverwritesWhatNowSitsAtTheOriginalPath() async throws {
        let fixture = try Fixture()
        let folder = try fixture.cache("app/node_modules")
        let outcomes = await fixture.engine.stage([VaporStageRequest(folderID: UUID(), url: folder, bytes: 0)])
        guard case .staged(_, let entry) = outcomes.first else { Issue.record("not staged"); return }
        // Something new appears where the folder was, such as a fresh `npm install`.
        let marker = try fixture.temp.file("app/node_modules/new.txt")
        let restored = await fixture.engine.restore([entry])
        #expect(restored == [.pathTaken(entry)])
        #expect(fixture.temp.exists(marker))
        #expect(!fixture.temp.exists(folder.appendingPathComponent("pkg0")))
        #expect(fixture.temp.exists(entry.stagedURL))
        #expect(fixture.ledger.read() == [entry])
    }

    @Test func removalDeletesStagedTreesAndClearsTheLedger() async throws {
        let fixture = try Fixture()
        let first = try fixture.cache("a/node_modules", files: 9)
        let second = try fixture.cache("b/target", files: 2)
        // A link inside a cache must go without deleting what it points to.
        let outside = try fixture.temp.file("keep/precious.txt")
        try FileManager.default.createSymbolicLink(at: first.appendingPathComponent("link"), withDestinationURL: outside)
        let outcomes = await fixture.engine.stage([
            VaporStageRequest(folderID: UUID(), url: first, bytes: 0), VaporStageRequest(folderID: UUID(), url: second, bytes: 0),
        ])
        let entries = outcomes.compactMap { outcome -> VaporLedgerEntry? in
            if case .staged(_, let entry) = outcome { return entry }
            return nil
        }
        #expect(entries.count == 2)
        let removed = await fixture.engine.remove(entries)
        #expect(Set(removed) == Set(entries.map(\.id)))
        for entry in entries { #expect(!fixture.temp.exists(entry.stagedURL)) }
        #expect(fixture.ledger.read().isEmpty)
        #expect(fixture.temp.exists(outside))
    }

    @Test func aMissingFolderFailsWithoutALedgerEntry() async throws {
        let fixture = try Fixture()
        let gone = fixture.temp.url.appendingPathComponent("app/node_modules")
        let id = UUID()
        let outcomes = await fixture.engine.stage([VaporStageRequest(folderID: id, url: gone, bytes: 0)])
        #expect(outcomes == [.failed(folderID: id, .missing)])
        #expect(fixture.ledger.read().isEmpty)
    }

    @Test func fallsBackToAnInPlaceRenameWhenStagingCantBeCreated() async throws {
        // The staging folder's parent is a file, so the staging folder can't be created.
        let fixture = try Fixture(stagingPath: "blocked/staging")
        try fixture.temp.file("blocked")
        let folder = try fixture.cache("app/node_modules")
        let outcomes = await fixture.engine.stage([VaporStageRequest(folderID: UUID(), url: folder, bytes: 0)])
        guard case .staged(_, let entry) = outcomes.first else { Issue.record("not staged: \(outcomes)"); return }
        #expect(entry.stagedURL.deletingLastPathComponent().path == folder.deletingLastPathComponent().path)
        #expect(entry.stagedURL.lastPathComponent.hasPrefix(".node_modules.dokk-vapor-"))
        #expect(fixture.temp.exists(entry.stagedURL))
        #expect(!fixture.temp.exists(folder))
    }

    @Test func recoveryFinishesStagedEntriesAndNeverRestores() async throws {
        let fixture = try Fixture()
        let staged = try fixture.cache("a/node_modules")
        let outcomes = await fixture.engine.stage([VaporStageRequest(folderID: UUID(), url: staged, bytes: 0)])
        guard case .staged(_, let stagedEntry) = outcomes.first else { Issue.record("not staged"); return }
        // An entry written before a rename that never happened: the folder is still in place.
        let untouched = try fixture.cache("b/node_modules")
        let interrupted = VaporLedgerEntry(id: UUID(), originalPath: untouched.path,
                                           stagedPath: fixture.staging.appendingPathComponent("never").path,
                                           bytes: 0, stagedAt: .now, state: .staging)
        // An entry written before a rename that did happen, with the update lost.
        let renamed = try fixture.cache("c/target")
        let renamedTarget = fixture.staging.appendingPathComponent("\(UUID().uuidString)-target")
        try FileManager.default.moveItem(at: renamed, to: renamedTarget)
        let lost = VaporLedgerEntry(id: UUID(), originalPath: renamed.path, stagedPath: renamedTarget.path,
                                    bytes: 0, stagedAt: .now, state: .staging)
        try fixture.ledger.write(fixture.ledger.read() + [interrupted, lost])

        // A new engine, as on the next launch.
        let relaunched = VaporDeletionEngine(ledger: fixture.ledger, location: VaporStagingLocation(homeStaging: fixture.staging))
        let removed = await relaunched.recover()
        #expect(removed == 2)
        #expect(!fixture.temp.exists(stagedEntry.stagedURL))
        #expect(!fixture.temp.exists(staged))
        #expect(!fixture.temp.exists(renamedTarget))
        #expect(!fixture.temp.exists(renamed))
        #expect(fixture.temp.exists(untouched.appendingPathComponent("pkg0/index.js")))
        #expect(fixture.ledger.read().isEmpty)
    }

    @Test func ledgerRoundTripsAndAnEmptyListRemovesTheFile() throws {
        let temp = try VaporTempDirectory("vapor-ledger")
        let ledger = VaporLedgerFile(url: temp.url.appendingPathComponent("nested/ledger.json"))
        #expect(ledger.read().isEmpty)
        let entry = VaporLedgerEntry(id: UUID(), originalPath: "/a/b", stagedPath: "/s/b", bytes: 12,
                                     stagedAt: Date(timeIntervalSince1970: 1_800_000_000), state: .staged)
        try ledger.write([entry])
        #expect(ledger.read() == [entry])
        try ledger.write([])
        #expect(!temp.exists(ledger.url))
    }

    @Test func aFolderSwappedForALinkIsNotStaged() async throws {
        let fixture = try Fixture()
        let folder = try fixture.cache("app/node_modules")
        let keep = try fixture.temp.file("elsewhere/keep/important.txt")
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: keep.deletingLastPathComponent())
        let outcomes = await fixture.engine.stage([VaporStageRequest(folderID: UUID(), url: folder, bytes: 0)])
        guard case .failed(_, let failure) = outcomes.first else { Issue.record("staged a link: \(outcomes)"); return }
        #expect(failure == .changed)
        #expect(fixture.temp.exists(keep))
        #expect(fixture.ledger.read().isEmpty)
    }

    @Test func removingAStagedLinkLeavesItsTargetAlone() async throws {
        let temp = try VaporTempDirectory("vapor-remover")
        let keep = try temp.file("target/keep/important.txt")
        let link = temp.url.appendingPathComponent("staged-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: keep.deletingLastPathComponent().deletingLastPathComponent())
        #expect(await VaporRemover().remove(link))
        #expect(VaporPathCheck(path: link.path) == .missing)
        #expect(temp.exists(keep))
    }

    @Test func aFolderHoldingTheStagingFolderIsRenamedInPlace() async throws {
        // Dropping the Caches folder that holds Vapor's own staging folder.
        let fixture = try Fixture(stagingPath: "Caches/DOKK/Vapor/staging")
        let caches = try fixture.cache("Caches")
        let outcomes = await fixture.engine.stage([VaporStageRequest(folderID: UUID(), url: caches, bytes: 0)])
        guard case .staged(_, let entry) = outcomes.first else { Issue.record("not staged: \(outcomes)"); return }
        #expect(entry.stagedURL.deletingLastPathComponent().path == caches.deletingLastPathComponent().path)
        #expect(entry.stagedURL.lastPathComponent.hasPrefix(".Caches.dokk-vapor-"))
        #expect(!fixture.temp.exists(caches))
    }

    @Test func anUnreadableLedgerStopsStagingAndIsKept() async throws {
        let fixture = try Fixture()
        let folder = try fixture.cache("app/node_modules")
        try FileManager.default.createDirectory(at: fixture.ledger.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fixture.ledger.url)
        let outcomes = await fixture.engine.stage([VaporStageRequest(folderID: UUID(), url: folder, bytes: 0)])
        guard case .failed = outcomes.first else { Issue.record("staged over a broken ledger: \(outcomes)"); return }
        #expect(fixture.temp.exists(folder))
        #expect(try Data(contentsOf: fixture.ledger.url) == Data("not json".utf8))
    }

    @Test func recoveryKeepsEntriesOnAnUnpluggedDisk() async throws {
        let fixture = try Fixture()
        let unplugged = VaporLedgerEntry(id: UUID(), originalPath: "/Volumes/Gone/app/node_modules",
                                         stagedPath: "/Volumes/Gone/.dokk-vapor/x-node_modules", bytes: 1,
                                         stagedAt: Date(timeIntervalSince1970: 1_800_000_000), state: .staged)
        try fixture.ledger.write([unplugged])
        #expect(await fixture.engine.recover() == 0)
        #expect(await fixture.engine.remove([unplugged]).isEmpty)
        #expect(fixture.ledger.read() == [unplugged])
    }

    @Test func aFailedLookupIsNeverReadAsGone() async throws {
        let fixture = try Fixture()
        let locked = try fixture.temp.folder("locked")
        let staged = try fixture.temp.folder("locked/x-node_modules")
        let entry = VaporLedgerEntry(id: UUID(), originalPath: fixture.temp.url.appendingPathComponent("app/node_modules").path,
                                     stagedPath: staged.path, bytes: 1,
                                     stagedAt: Date(timeIntervalSince1970: 1_800_000_000), state: .staged)
        try fixture.ledger.write([entry])
        // Without search permission on its parent, `lstat` on the staged folder fails with EACCES.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        #expect(VaporPathCheck(path: staged.path) == .unknown)
        #expect(await fixture.engine.recover() == 0)
        #expect(fixture.ledger.read() == [entry])
    }

    @Test func removalLeavesAnUnreadableLedgerAsItIs() async throws {
        let fixture = try Fixture()
        let folder = try fixture.cache("app/node_modules")
        let outcomes = await fixture.engine.stage([VaporStageRequest(folderID: UUID(), url: folder, bytes: 0)])
        guard case .staged(_, let entry) = outcomes.first else { Issue.record("not staged"); return }
        try Data("not json".utf8).write(to: fixture.ledger.url)
        #expect(await fixture.engine.remove([entry]) == [entry.id])
        #expect(!fixture.temp.exists(entry.stagedURL))
        #expect(try Data(contentsOf: fixture.ledger.url) == Data("not json".utf8))
    }

    @Test(arguments: [(EACCES, VaporStagingFailure.permissionDenied), (EPERM, .permissionDenied), (ENOENT, .missing),
                      (EXDEV, .unsupportedVolume), (EROFS, .unsupportedVolume), (EBUSY, .other(EBUSY))])
    func errnoMapsToARowReason(code: Int32, failure: VaporStagingFailure) {
        #expect(VaporStagingFailure(errno: code) == failure)
    }
}
