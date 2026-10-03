import Foundation
import Testing
@testable import DeeDock

/// File drops onto a drive: copy keeps the source, Shift-move removes it, and existing files on the
/// drive are never replaced.
@MainActor
struct VolumeDropTests {
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func transfer(_ urls: [URL], to destination: URL, move: Bool) async -> String? {
        let lease = FolderResourceAccess(FolderReference(url: destination, name: "Drive", bookmarkData: Data()))
        return await withCheckedContinuation { continuation in
            FolderFileDrop.copy(urls, to: destination, lease: lease, move: move) { continuation.resume(returning: $0) }
        }
    }

    @Test("Copy leaves the source; move removes it; both land in the destination")
    func copyAndMove() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), drive = root.appendingPathComponent("drive")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let copied = source.appendingPathComponent("copied.txt"), moved = source.appendingPathComponent("moved.txt")
        try Data("a".utf8).write(to: copied)
        try Data("b".utf8).write(to: moved)

        #expect(await transfer([copied], to: drive, move: false) == nil)
        #expect(FileManager.default.fileExists(atPath: copied.path))
        #expect(FileManager.default.fileExists(atPath: drive.appendingPathComponent("copied.txt").path))

        #expect(await transfer([moved], to: drive, move: true) == nil)
        #expect(!FileManager.default.fileExists(atPath: moved.path))
        #expect(try Data(contentsOf: drive.appendingPathComponent("moved.txt")) == Data("b".utf8))
    }

    @Test("A name already on the drive refuses the whole batch and keeps the source")
    func collision() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), drive = root.appendingPathComponent("drive")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let file = source.appendingPathComponent("report.pdf")
        try Data("new".utf8).write(to: file)
        try Data("old".utf8).write(to: drive.appendingPathComponent("report.pdf"))

        #expect(await transfer([file], to: drive, move: true) != nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: drive.appendingPathComponent("report.pdf")) == Data("old".utf8))
    }
}
