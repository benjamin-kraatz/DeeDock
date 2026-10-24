import Foundation
import Testing
@testable import DeeDock

/// The last check before anything goes to the Trash.
struct AppUninstallPathPolicyTests {
    private let home = URL(fileURLWithPath: "/Users/test")

    @Test func directChildrenOfDataFoldersAreAllowed() {
        for path in ["Library/Caches/com.example.Editor", "Library/Containers/com.example.Editor",
                     "Library/Preferences/ByHost/com.example.Editor.1234.plist", "Library/LaunchAgents/com.example.Editor.plist"] {
            #expect(AppUninstallPathPolicy.allowsData(home.appendingPathComponent(path), home: home), "\(path)")
        }
        #expect(AppUninstallPathPolicy.allowsData(URL(fileURLWithPath: "/Library/LaunchDaemons/com.example.helper.plist"), home: home))
    }

    @Test func dataFoldersThemselvesAndAnythingElseAreRefused() {
        for path in ["Library/Caches", "Library", "Documents/com.example.Editor", "Library/Caches/com.example.Editor/Sub",
                     "Library/Caches/.DS_Store", "Library/Keychains/login.keychain-db", "Desktop"] {
            #expect(!AppUninstallPathPolicy.allowsData(home.appendingPathComponent(path), home: home), "\(path)")
        }
        #expect(!AppUninstallPathPolicy.allowsData(URL(fileURLWithPath: "/Library/Application Support"), home: home))
        #expect(!AppUninstallPathPolicy.allowsData(URL(fileURLWithPath: "/System/Library/Caches/x"), home: home))
        #expect(!AppUninstallPathPolicy.allowsData(home.appendingPathComponent("Library/Caches/../Keychains/x"), home: home))
    }

    @Test func onlyUnprotectedDotFoldersInTheHomeFolder() {
        #expect(AppUninstallPathPolicy.allowsData(home.appendingPathComponent(".editor"), home: home))
        for name in [".ssh", ".Trash", ".config", ".zshrc", "Documents", "."] {
            #expect(!AppUninstallPathPolicy.allowsData(home.appendingPathComponent(name), home: home), "\(name)")
        }
    }

    @Test func systemAppsAreNeverOffered() {
        #expect(!AppUninstallPathPolicy.allowsApp(URL(fileURLWithPath: "/System/Applications/Notes.app")))
        #expect(!AppUninstallPathPolicy.allowsApp(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")))
    }

    @Test func plainAppBundlesAreOfferedButNotNestedOnesOrDOKK() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-policy-\(UUID().uuidString)")
        let app = folder.appendingPathComponent("Editor.app")
        let nested = app.appendingPathComponent("Contents/Library/LoginItems/Helper.app")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(AppUninstallPathPolicy.allowsApp(app, ownBundle: URL(fileURLWithPath: "/Applications/DOKK.app")))
        #expect(!AppUninstallPathPolicy.allowsApp(nested, ownBundle: URL(fileURLWithPath: "/Applications/DOKK.app")))
        #expect(!AppUninstallPathPolicy.allowsApp(app, ownBundle: app))
        #expect(!AppUninstallPathPolicy.allowsApp(folder, ownBundle: URL(fileURLWithPath: "/Applications/DOKK.app")))
        #expect(!AppUninstallPathPolicy.allowsApp(folder.appendingPathComponent("Missing.app"),
                                                  ownBundle: URL(fileURLWithPath: "/Applications/DOKK.app")))
    }
}
