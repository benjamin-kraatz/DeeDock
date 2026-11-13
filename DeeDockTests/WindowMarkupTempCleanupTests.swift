import Foundation
import Testing
@testable import DeeDock

/// Markup drag-out pictures are swept from the temporary folder, and nothing else is touched.
struct WindowMarkupTempCleanupTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A fresh folder standing in for `$TMPDIR`, removed afterwards.
    private func withSandbox(_ body: (URL) throws -> Void) throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("markup-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try body(sandbox)
    }

    /// Writes a picture into `name` inside `sandbox`, then dates the folder `age` seconds back.
    @discardableResult
    private func exportFolder(_ name: String, in sandbox: URL, age: TimeInterval) throws -> URL {
        let folder = sandbox.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: folder.appendingPathComponent("Window.png"))
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: folder.path)
        return folder
    }

    @Test("Old export folders go; recent ones and everything else stay")
    func sweepsOnlyOldExportFolders() throws {
        try withSandbox { sandbox in
            let old = try exportFolder("DeeDockMarkup-\(UUID().uuidString)", in: sandbox, age: 3_600)
            let recent = try exportFolder("DeeDockMarkup-\(UUID().uuidString)", in: sandbox, age: 30)
            // Same prefix but not a UUID, and an unrelated folder: never touched.
            let lookalike = try exportFolder("DeeDockMarkup-notes", in: sandbox, age: 3_600)
            let other = try exportFolder("SomethingElse-\(UUID().uuidString)", in: sandbox, age: 3_600)

            let removed = WindowMarkupTempCleanup(directory: sandbox, now: { now }).run()

            #expect(removed == 1)
            #expect(!FileManager.default.fileExists(atPath: old.path))
            #expect(FileManager.default.fileExists(atPath: recent.path))
            #expect(FileManager.default.fileExists(atPath: lookalike.path))
            #expect(FileManager.default.fileExists(atPath: other.path))
        }
    }

    @Test("A link or file with an export folder's name is left alone, and its target too")
    func neverFollowsLinks() throws {
        try withSandbox { sandbox in
            let target = try exportFolder("keep", in: sandbox, age: 3_600)
            let link = sandbox.appendingPathComponent("DeeDockMarkup-\(UUID().uuidString)")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let file = sandbox.appendingPathComponent("DeeDockMarkup-\(UUID().uuidString)")
            try Data("x".utf8).write(to: file)

            #expect(WindowMarkupTempCleanup(directory: sandbox, now: { now.addingTimeInterval(86_400) }).run() == 0)
            #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
            #expect(FileManager.default.fileExists(atPath: file.path))
            #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("Window.png").path))
        }
    }

    @Test("Export folder names are the prefix and a UUID, nothing looser")
    func folderNames() {
        #expect(WindowMarkupTempCleanup.isExportFolderName("DeeDockMarkup-\(UUID().uuidString)"))
        #expect(!WindowMarkupTempCleanup.isExportFolderName("DeeDockMarkup-"))
        #expect(!WindowMarkupTempCleanup.isExportFolderName("DeeDockMarkup-\(UUID().uuidString)-x"))
        #expect(!WindowMarkupTempCleanup.isExportFolderName("deedockmarkup-\(UUID().uuidString)"))
        #expect(!WindowMarkupTempCleanup.isExportFolderName("X-DeeDockMarkup-\(UUID().uuidString)"))
    }
}
