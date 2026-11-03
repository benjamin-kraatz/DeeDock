import Foundation
import Testing
@testable import DeeDock

/// The retired Museum's clipboard copies are deleted once, and nothing beside them is touched.
@MainActor
struct ClipboardMuseumCleanupTests {
    @Test("Deletes the Museum folder, leaves its neighbours, and runs once")
    func deletesOnlyTheMuseum() throws {
        try withSandbox { defaults, support in
            let museum = support.appendingPathComponent("ClipboardMuseum", isDirectory: true)
            try write("{}", to: museum.appendingPathComponent("collection.json"))
            try write("png", to: museum.appendingPathComponent("Images/\(UUID().uuidString).png"))
            try write("sealed", to: museum.appendingPathComponent("Vault/\(UUID().uuidString).sealed"))
            // The Shelf's pasted images live beside the Museum and must survive.
            let shelf = support.appendingPathComponent("Clipboard/Clipboard-1.png")
            try write("shelf", to: shelf)
            defaults.set(true, forKey: "unrelated.key")

            let cleanup = ClipboardMuseumCleanup(defaults: defaults, directory: museum)

            #expect(cleanup.run())
            #expect(!FileManager.default.fileExists(atPath: museum.path))
            #expect(FileManager.default.fileExists(atPath: shelf.path))
            #expect(defaults.bool(forKey: "unrelated.key"))
            #expect(defaults.bool(forKey: ClipboardMuseumCleanup.completedKey))

            // A Museum folder that reappears, say from a restored backup, is left for the person.
            try write("{}", to: museum.appendingPathComponent("collection.json"))
            #expect(cleanup.run())
            #expect(FileManager.default.fileExists(atPath: museum.path))
        }
    }

    @Test("A Mac that never used the Museum completes without errors")
    func nothingToDelete() throws {
        try withSandbox { defaults, support in
            let cleanup = ClipboardMuseumCleanup(defaults: defaults,
                                                 directory: support.appendingPathComponent("ClipboardMuseum"))
            #expect(cleanup.run())
            #expect(defaults.bool(forKey: ClipboardMuseumCleanup.completedKey))
        }
    }

    @Test("A folder that cannot be deleted is retried at the next launch")
    func failedDeletionRetries() throws {
        try withSandbox { defaults, support in
            let museum = support.appendingPathComponent("ClipboardMuseum", isDirectory: true)
            try write("{}", to: museum.appendingPathComponent("collection.json"))
            // Without write permission on the parent, the folder cannot be removed.
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: support.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path) }

            let cleanup = ClipboardMuseumCleanup(defaults: defaults, directory: museum)
            #expect(!cleanup.run())
            #expect(!defaults.bool(forKey: ClipboardMuseumCleanup.completedKey))

            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
            #expect(cleanup.run())
            #expect(!FileManager.default.fileExists(atPath: museum.path))
        }
    }

    @Test("An unresolvable folder skips without deleting anything and retries later")
    func unresolvedDirectorySkips() throws {
        try withSandbox { defaults, _ in
            let cleanup = ClipboardMuseumCleanup(defaults: defaults, directory: nil)
            #expect(!cleanup.run())
            #expect(!defaults.bool(forKey: ClipboardMuseumCleanup.completedKey))
        }
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func withSandbox(_ body: (UserDefaults, URL) throws -> Void) throws {
        let suite = "clipboard-museum.cleanup.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardMuseumCleanupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: support)
        }
        try body(defaults, support)
    }
}
