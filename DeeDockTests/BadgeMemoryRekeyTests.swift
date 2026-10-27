import Foundation
import Testing
@testable import DeeDock

/// Saved badge history was keyed by the path string from before symlink resolution.
@MainActor
struct BadgeMemoryRekeyTests {
    @Test("A saved symlink path keeps its baseline and is not lowercased")
    func rekeyKeepsBaseline() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ddock-badge-rekey-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let system = root.appendingPathComponent("System/Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        let real = system.appendingPathComponent("Safari.app", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let link = applications.appendingPathComponent("Safari.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let now = Date()
        var document = BadgeMemoryDocument()
        document.apps[link.path] = BadgeAppMemory(
            checked: BadgeCheck(value: .count(37), date: now),
            changes: [BadgeChange(value: .count(37), date: now)],
            touched: now)

        let suite = "BadgeRekey.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(document), forKey: "dock.badge-memory.v1")

        let store = BadgeMemoryStore(defaults: defaults)
        store.start()
        let canonical = DockBadgePath.key(for: link)
        let app = try #require(store.document.apps[canonical])
        #expect(store.document.apps.count == 1)
        #expect(store.document.apps[link.path] == nil || link.path == canonical)
        #expect(badgeAppName(canonical) == "Safari")
        #expect(canonical.hasSuffix("Safari.app"))
        #expect(app.checked?.value == .count(37))
        #expect(app.changes.map(\.value) == [.count(37)])

        store.observe([canonical: .count(37)], at: now.addingTimeInterval(5))

        let after = try #require(store.document.apps[canonical])
        #expect(store.document.apps.count == 1)
        #expect(badgeAppName(canonical) == "Safari")
        #expect(after.checked?.value == .count(37))
        #expect(after.changes.map(\.value) == [.count(37)])
    }
}
