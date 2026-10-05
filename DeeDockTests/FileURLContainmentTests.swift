import Foundation
import Testing
@testable import DeeDock

/// Folder containment. Resolving tests use a temporary directory. The lexical test does not.
nonisolated struct FileURLContainmentTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ddock-containment-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("An exact path and a trailing slash are the same folder")
    func exactMatchAndTrailingSlash() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let slashed = URL(fileURLWithPath: folder.path + "/", isDirectory: true)
        #expect(folder.isSameOrDescendant(of: folder))
        #expect(slashed.isSameOrDescendant(of: folder))
        #expect(folder.isSameOrDescendant(of: slashed))
    }

    @Test("A case-only difference follows the volume")
    func caseOnlyDifference() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // Neither path is created, so symlink resolution cannot rewrite the last component's case.
        let upper = root.appendingPathComponent("Folder", isDirectory: true)
        let lower = root.appendingPathComponent("folder", isDirectory: true)
        let sensitive = (try? root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames == true
        #expect(lower.isSameOrDescendant(of: upper) == !sensitive)
        let nested = lower.appendingPathComponent("nested", isDirectory: true)
        #expect(nested.isSameOrDescendant(of: upper) == !sensitive)
    }

    @Test("A descendant is inside its folder, and /a/bc is not inside /a/b")
    func descendantAndSharedPrefix() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = root.appendingPathComponent("a", isDirectory: true)
        let folder = parent.appendingPathComponent("b", isDirectory: true)
        let sibling = parent.appendingPathComponent("bc", isDirectory: true)
        let child = folder.appendingPathComponent("c", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        #expect(child.isSameOrDescendant(of: folder))
        #expect(!folder.isSameOrDescendant(of: child))
        #expect(!sibling.isSameOrDescendant(of: folder))
        #expect(!folder.isSameOrDescendant(of: sibling))
        #expect(!child.isSameOrDescendant(of: sibling))
    }

    @Test("Lexical containment folds case, keeps /a/bc outside /a/b, and accepts a trailing slash")
    func lexicalContainment() {
        let folder = URL(fileURLWithPath: "/a/b", isDirectory: true)
        let slashed = URL(fileURLWithPath: "/a/b/", isDirectory: true)
        let otherCase = URL(fileURLWithPath: "/A/B", isDirectory: true)
        let sibling = URL(fileURLWithPath: "/a/bc", isDirectory: true)
        #expect(slashed.isSameOrDescendant(of: folder, resolvingSymlinks: false))
        #expect(folder.isSameOrDescendant(of: slashed, resolvingSymlinks: false))
        #expect(otherCase.isSameOrDescendant(of: folder, resolvingSymlinks: false))
        #expect(!sibling.isSameOrDescendant(of: folder, resolvingSymlinks: false))
        #expect(!folder.isSameOrDescendant(of: sibling, resolvingSymlinks: false))
    }

    @Test("A symlink resolves to the same folder as its target")
    func symlink() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real", isDirectory: true)
        let child = real.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        #expect(link.isSameOrDescendant(of: real))
        #expect(real.isSameOrDescendant(of: link))
        #expect(child.isSameOrDescendant(of: link))
        #expect(link.appendingPathComponent("child").isSameOrDescendant(of: real))
        #expect(!outside.isSameOrDescendant(of: link))
    }
}
