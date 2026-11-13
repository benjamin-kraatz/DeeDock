import Foundation
import Testing
@testable import DeeDock

/// Which items go to Finder, which resolves symbolic links, instead of DOKK's own move to the Trash.
struct AppUninstallWorkspaceTests {
    @Test func aSymbolicLinkNeverGoesToFinder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-workspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // A folder only root may write to, which on its own needs Finder.
        let protected = URL(fileURLWithPath: "/Library")
        let link = folder.appendingPathComponent("com.example.Editor")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: protected)

        #expect(AppUninstallWorkspace.needsFinder(protected))
        #expect(!AppUninstallWorkspace.needsFinder(link))
    }
}
