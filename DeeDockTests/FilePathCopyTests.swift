import Foundation
import Testing
@testable import DeeDock

/// Path text for the Copy Path and Copy Relative Path commands. Only the symlink test touches disk.
nonisolated struct FilePathCopyTests {
    @Test("A direct child is relative to its stack root")
    func directChild() {
        let root = URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true)
        #expect(FilePathCopy.relativePath(of: root.appendingPathComponent("file.txt"), in: root) == "./file.txt")
    }

    @Test("A nested item keeps the folders between it and the root")
    func nestedItem() {
        let root = URL(fileURLWithPath: "/Volumes/Drive/", isDirectory: true)
        let file = URL(fileURLWithPath: "/Volumes/Drive/folder/file.txt")
        #expect(FilePathCopy.relativePath(of: file, in: root) == "./folder/file.txt")
    }

    @Test("A sibling prefix is not treated as containment")
    func siblingPrefix() {
        let root = URL(fileURLWithPath: "/a/b", isDirectory: true)
        #expect(FilePathCopy.relativePath(of: URL(fileURLWithPath: "/a/bc/file.txt"), in: root) == "./file.txt")
    }

    @Test("The root itself is the current directory")
    func rootItself() {
        let root = URL(fileURLWithPath: "/a/b", isDirectory: true)
        #expect(FilePathCopy.relativePath(of: root, in: root) == ".")
    }

    @Test("A symlinked root still yields the nested path")
    func symlinkedRoot() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ddock-pathcopy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appendingPathComponent("Real", isDirectory: true)
        try FileManager.default.createDirectory(at: real.appendingPathComponent("folder"),
                                                withIntermediateDirectories: true)
        let link = base.appendingPathComponent("Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let file = real.appendingPathComponent("folder/file.txt")
        #expect(FilePathCopy.relativePath(of: file, in: link) == "./folder/file.txt")
    }

    @Test("An absolute path has no percent encoding or trailing slash")
    func absolutePath() {
        let folder = URL(fileURLWithPath: "/Users/me/My Files/", isDirectory: true)
        #expect(FilePathCopy.path(of: folder) == "/Users/me/My Files")
    }
}
