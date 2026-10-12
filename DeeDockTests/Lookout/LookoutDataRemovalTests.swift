import Foundation
import Testing
@testable import DeeDock

/// "Delete index and model": the right files go from a temporary `LookoutPaths` base and nothing else does, and the
/// engine closes the index in the service and here before anything is deleted.
@MainActor
struct LookoutDataRemovalTests {
    private let root: URL
    private let paths: LookoutPaths

    init() {
        root = FileManager.default.temporaryDirectory
            .appending(path: "LookoutRemovalTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        paths = LookoutPaths(base: root.appending(path: "Lookout", directoryHint: .isDirectory))
    }

    /// The index with its WAL and SHM, both models, a partial download, a log, and a file beside the base.
    private func makeFiles() throws -> (gone: [URL], kept: [URL]) {
        let fileManager = FileManager.default
        for folder in [paths.models, paths.partialDownloads, paths.logs, root.appending(path: "Other")] {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let gone = paths.indexFiles.prefix(3) + [paths.models.appending(path: ModelFiles.text.name),
                                                 paths.models.appending(path: ModelFiles.media.name),
                                                 paths.partialDownloads.appending(path: "x.gguf.partial")]
        let kept = [paths.logs.appending(path: "index-service.log"), root.appending(path: "Other/notes.txt"),
                    root.appending(path: "index.sqlite")]
        for file in Array(gone) + kept { try Data("x".utf8).write(to: file) }
        return (Array(gone), kept)
    }

    @Test("Removes the index files, Models and partial downloads, and nothing else")
    func removesOnlyLookoutData() throws {
        let (gone, kept) = try makeFiles()
        try LookoutDataRemoval.removeNow(in: paths)
        for file in gone { #expect(!FileManager.default.fileExists(atPath: file.path), "\(file.lastPathComponent)") }
        #expect(!FileManager.default.fileExists(atPath: paths.models.path))
        #expect(!FileManager.default.fileExists(atPath: paths.partialDownloads.path))
        for file in kept { #expect(FileManager.default.fileExists(atPath: file.path), "\(file.path)") }
        try? FileManager.default.removeItem(at: root)
    }

    @Test("Removing twice, or with nothing there, is fine")
    func idempotent() throws {
        try LookoutDataRemoval.removeNow(in: paths)
        _ = try makeFiles()
        try LookoutDataRemoval.removeNow(in: paths)
        try LookoutDataRemoval.removeNow(in: paths)
        try? FileManager.default.removeItem(at: root)
    }

    @Test("The engine closes the index in the service and here, stops, forgets setup, then deletes")
    func engineDeletes() async throws {
        let (gone, kept) = try makeFiles()
        let connection = FakeIndexConnection()
        let reader = FakeIndexReader()
        let engine = LookoutEngine(settings: .activeForTests, repository: nil, connection: connection,
                                   encoder: FakeQueryEncoder(), reader: reader, monitor: FakeMonitor(),
                                   power: FakePowerPolicy(), paths: paths, canRun: true)
        engine.start()
        #expect(engine.isRunning)
        try await engine.deleteIndexAndModel()
        let calls = connection.calls.filter { $0 == .closeIndex || $0 == .invalidate }
        #expect(calls == [.closeIndex, .invalidate], "closed before the connection goes")
        #expect(await reader.closed == 1)
        #expect(!engine.isRunning && engine.status == .notSetUp && engine.settings == LookoutSettings())
        for file in gone { #expect(!FileManager.default.fileExists(atPath: file.path)) }
        for file in kept { #expect(FileManager.default.fileExists(atPath: file.path)) }
        try? FileManager.default.removeItem(at: root)
    }

    @Test("Read everything again asks a running service to reset, and nothing while Lookout is off")
    func readEverythingAgain() {
        let connection = FakeIndexConnection()
        let engine = LookoutEngine(settings: .activeForTests, repository: nil, connection: connection,
                                   encoder: FakeQueryEncoder(), reader: FakeIndexReader(), monitor: FakeMonitor(),
                                   power: FakePowerPolicy(), paths: paths, canRun: true)
        engine.readEverythingAgain()
        #expect(!connection.calls.contains(.resetIndex))
        engine.start()
        engine.readEverythingAgain()
        #expect(connection.calls.last == .resetIndex)
    }
}
