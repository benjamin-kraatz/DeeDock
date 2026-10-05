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
        let key = DockBadgePath.key(for: link)
        #expect(key == DockBadgePath.key(for: real))
        #expect(key.hasSuffix("Safari.app"))
    }

    @Test("Case-only spellings follow the volume")
    func caseOnlySpelling() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("Mail.app", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let otherCase = root.appendingPathComponent("mail.app")
        #expect(DockBadgePath.key(for: real).hasSuffix("Mail.app"))
        #expect(DockBadgePath.sameInstallation(real.path, otherCase.path) == !caseSensitive(root))
        if caseSensitive(root) {
            #expect(DockBadgePath.key(for: real) != DockBadgePath.key(for: otherCase))
        } else {
            #expect(DockBadgePath.key(for: otherCase) == DockBadgePath.key(for: real))
        }
    }

    @Test("A missing path keeps its spelling")
    func missingPath() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let upper = root.appendingPathComponent("Missing.app")
        let lower = root.appendingPathComponent("missing.app")
        #expect(DockBadgePath.key(for: upper).hasSuffix("Missing.app"))
        #expect(DockBadgePath.key(for: lower).hasSuffix("missing.app"))
        #expect(DockBadgePath.sameInstallation(upper.path, lower.path) == !caseSensitive(root))
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
