import Foundation
import Testing
@testable import DeeDock

/// What the inspector reads from an app bundle and the folder around it.
struct AppUninstallInspectorTests {
    @Test func aSiblingUninstallerMustBeNamedAfterTheApp() throws {
        // Outside the Applications folders, like an app left in Downloads.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-inspector-\(UUID().uuidString)")
        let app = folder.appendingPathComponent("Editor.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Cleaner Uninstaller.app"),
                                                withIntermediateDirectories: true)

        #expect(AppUninstallInspector.inspect(app, name: "Editor").vendorUninstaller == nil)

        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Editor Uninstaller.app"),
                                                withIntermediateDirectories: true)
        #expect(AppUninstallInspector.inspect(app, name: "Editor").vendorUninstaller?.lastPathComponent == "Editor Uninstaller.app")
    }
}
