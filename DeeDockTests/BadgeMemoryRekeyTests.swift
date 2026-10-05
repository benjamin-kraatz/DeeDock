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
        let removed = system.appendingPathComponent("Removed.app", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: removed, withIntermediateDirectories: true)
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let link = applications.appendingPathComponent("Safari.app")
        let removedLink = applications.appendingPathComponent("Removed.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try FileManager.default.createSymbolicLink(at: removedLink, withDestinationURL: removed)

        let now = Date()
        let session = FocusSession(id: UUID(), modeID: UUID(), modeName: "Focus", duration: 1500,
                                   remainingWhenPaused: 1500, deadline: now.addingTimeInterval(1500), phase: .running)
        var active = BadgeFocusDigest(id: session.id, modeName: "Focus", started: now, ended: nil,
                                       deadline: session.deadline)
        active.rows[link.path] = BadgeDigestRow(first: .count(37), last: .count(37))
        active.excludedPaths = [removedLink.path]
        var completed = BadgeFocusDigest(id: UUID(), modeName: "Earlier", started: now.addingTimeInterval(-100),
                                         ended: now.addingTimeInterval(-10), deadline: now.addingTimeInterval(-10))
        completed.rows[link.path] = BadgeDigestRow(first: .count(37), last: .count(41), changes: 1)
        var document = BadgeMemoryDocument(lastSessionID: session.id)
        document.apps[link.path] = BadgeAppMemory(
            checked: BadgeCheck(value: .count(37), date: now),
            changes: [BadgeChange(value: .count(37), date: now)],
            touched: now)
        document.active = active
        document.digests = [completed]

        let suite = "BadgeRekey.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(document), forKey: "dock.badge-memory.v1")

        let store = BadgeMemoryStore(defaults: defaults)
        store.start(session: session, at: now)
        let canonical = DockBadgePath.key(for: link)
        let removedKey = DockBadgePath.key(for: removedLink)
        let app = try #require(store.document.apps[canonical])
        #expect(store.document.apps.count == 1)
        #expect(store.document.apps[link.path] == nil || link.path == canonical)
        #expect(badgeAppName(canonical) == "Safari")
        #expect(canonical.hasSuffix("Safari.app"))
        #expect(app.checked?.value == .count(37))
        #expect(app.changes.map(\.value) == [.count(37)])

        store.observe([canonical: .count(37)], session: session, at: now.addingTimeInterval(5),
                      scanStarted: now.addingTimeInterval(5))

        let after = try #require(store.document.apps[canonical])
        #expect(store.document.apps.count == 1)
        #expect(badgeAppName(canonical) == "Safari")
        #expect(after.checked?.value == .count(37))
        #expect(after.changes.map(\.value) == [.count(37)])
        #expect(store.document.active?.rows[canonical]?.first == .count(37))
        #expect(store.document.active?.rows.count == 1)
        #expect(store.document.active?.excludedPaths == [removedKey])
        #expect(badgeAppName(removedKey) == "Removed")
        let digest = try #require(store.document.digests.first)
        #expect(digest.rows[canonical]?.last == .count(41))
        #expect(digest.rows[canonical]?.changes == 1)
        #expect(digest.rows.count == 1)
    }
}
