import Foundation
import Testing
@testable import DeeDock

/// Badge installation keys. Symlink tests use a temporary directory.
nonisolated struct DockBadgePathTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ddock-badge-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func caseSensitive(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames == true
    }

    @Test("A pin symlink and the Dock bundle path share one badge key")
    func symlinkAndTarget() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let system = root.appendingPathComponent("System/Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        let real = system.appendingPathComponent("Safari.app", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let link = applications.appendingPathComponent("Safari.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(link.standardizedFileURL.path != real.standardizedFileURL.path)
        #expect(DockBadgePath.key(for: link) == DockBadgePath.key(for: real))
        #expect(DockBadgePath.key(for: link).hasSuffix(".app"))
    }

    @Test("Case-only spellings follow the volume")
    func caseOnlySpelling() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("Mail.app", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let otherCase = root.appendingPathComponent("mail.app")
        if caseSensitive(root) {
            #expect(DockBadgePath.key(for: real) != DockBadgePath.key(for: otherCase))
        } else {
            let key = DockBadgePath.key(for: otherCase)
            #expect(key == DockBadgePath.key(for: real))
            #expect(key == key.lowercased(with: Locale(identifier: "en_US_POSIX")))
        }
    }

    @Test("A missing path folds case only on a case-insensitive volume")
    func missingPath() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let upper = root.appendingPathComponent("Missing.app")
        let lower = root.appendingPathComponent("missing.app")
        let same = DockBadgePath.key(for: upper) == DockBadgePath.key(for: lower)
        #expect(same == !caseSensitive(root))
    }

    @Test("Two installations stay distinct")
    func distinctApps() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let mail = root.appendingPathComponent("Mail.app", isDirectory: true)
        let messages = root.appendingPathComponent("Messages.app", isDirectory: true)
        try FileManager.default.createDirectory(at: mail, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: messages, withIntermediateDirectories: true)
        #expect(DockBadgePath.key(for: mail) != DockBadgePath.key(for: messages))
    }
}
