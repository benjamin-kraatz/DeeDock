import Foundation
import Testing
@testable import DeeDock

/// Quarantine URL matching. Each test uses its own defaults suite and temporary directory.
@MainActor
struct QuarantineStoreTests {
    private struct Fixture {
        let store: QuarantineStore
        let defaults: UserDefaults
        let suite: String
        let root: URL
        let folder: URL
        let child: URL
        let link: URL
        let sibling: URL
        let prefixTwin: URL

        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeFixture() throws -> Fixture {
        let suite = "QuarantineStore.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ddock-quarantine-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("child.txt")
        try FileManager.default.createDirectory(at: child.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("child".utf8).write(to: child)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        let sibling = root.appendingPathComponent("FolderSibling", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let prefixTwin = root.appendingPathComponent("Folder.txt")
        try Data("twin".utf8).write(to: prefixTwin)
        return Fixture(
            store: QuarantineStore(defaults: defaults),
            defaults: defaults,
            suite: suite,
            root: root,
            folder: folder,
            child: child,
            link: link,
            sibling: sibling,
            prefixTwin: prefixTwin)
    }

    @Test("A stamped folder blocks its target, a symlink, and a descendant")
    func symlinkAndDescendant() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        #expect(!store.blocks(fixture.folder))
        #expect(store.toggle(id: fixture.folder.path, url: fixture.folder, name: "Folder") != nil)

        let slashed = URL(fileURLWithPath: fixture.folder.path + "/", isDirectory: true)
        let childLink = fixture.root.appendingPathComponent("child-link")
        try FileManager.default.createSymbolicLink(at: childLink, withDestinationURL: fixture.child)

        #expect(store.blocks(fixture.folder))
        #expect(store.blocks(slashed))
        #expect(store.blocks(fixture.child))
        #expect(store.blocks(fixture.link))
        #expect(store.blocks(fixture.link.appendingPathComponent("nested").appendingPathComponent("child.txt")))
        #expect(store.blocks(childLink))
        #expect(store.contains("other-route", url: fixture.child))
        #expect(!store.blocks(fixture.sibling))
        #expect(!store.blocks(fixture.prefixTwin))
        #expect(!store.blocks(fixture.root))
        #expect(throws: (any Error).self) { try store.requireAllowed(fixture.child) }
        try store.requireAllowed(fixture.sibling)

        let reloaded = QuarantineStore(defaults: fixture.defaults)
        #expect(reloaded.blocks(childLink))
        #expect(reloaded.blocks(fixture.link.appendingPathComponent("nested")))
        #expect(!reloaded.blocks(fixture.prefixTwin))

        let record = try #require(store.records.first)
        #expect(store.release(record))
        #expect(!store.blocks(fixture.child))
        #expect(!store.blocks(fixture.link))
    }

    @Test("A stamp on the symlink covers the real folder and its descendants")
    func stampOnSymlink() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        #expect(fixture.store.toggle(id: fixture.link.path, url: fixture.link, name: "Link") != nil)
        #expect(fixture.store.blocks(fixture.link))
        #expect(fixture.store.blocks(fixture.folder))
        #expect(fixture.store.blocks(fixture.child))
        #expect(!fixture.store.blocks(fixture.sibling))
        #expect(!fixture.store.blocks(fixture.prefixTwin))
    }

    @Test("A case-only difference follows the volume")
    func caseOnlyDifference() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        #expect(fixture.store.toggle(id: fixture.folder.path, url: fixture.folder, name: "Folder") != nil)
        let otherCase = fixture.root.appendingPathComponent("folder", isDirectory: true)
        let sensitive = (try? fixture.root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames == true
        #expect(fixture.store.blocks(otherCase) == !sensitive)
        let otherChild = otherCase.appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("child.txt")
        #expect(fixture.store.blocks(otherChild) == !sensitive)
    }

    @Test("A saved id still matches when the URL is outside the stamp")
    func identityMatch() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        #expect(fixture.store.toggle(id: "pin-id", url: fixture.folder, name: "Folder") != nil)
        #expect(fixture.store.contains("pin-id", url: fixture.sibling))
        #expect(!fixture.store.contains("other-pin", url: fixture.sibling))
        #expect(!fixture.store.blocks(fixture.sibling))
    }

    @Test("Unreadable flag data blocks opening and is left untouched")
    func unreadableBlocks() throws {
        let suite = "QuarantineStore.unreadable.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let junk = Data("nope".utf8)
        defaults.set(junk, forKey: "quarantine.records.v1")
        let store = QuarantineStore(defaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/ddock-quarantine-unreadable")
        #expect(store.unreadable)
        #expect(store.blocks(url))
        #expect(store.toggle(id: "x", url: url, name: "x") == nil)
        #expect(defaults.data(forKey: "quarantine.records.v1") == junk)
    }
}
