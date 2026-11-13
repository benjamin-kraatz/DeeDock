import Foundation
import Testing
@testable import DeeDock

/// What Vapor accepts and refuses, against fake paths with fixed file-system answers.
struct VaporDropPolicyTests {
    private let home = URL(fileURLWithPath: "/Users/test")

    private func policy(files: Set<String> = [], packages: Set<String> = [], links: Set<String> = [],
                        missing: Set<String> = [], volumes: Set<String> = []) -> VaporDropPolicy {
        VaporDropPolicy(home: home, inspector: VaporFileInspector(
            kind: { url in
                if missing.contains(url.path) { return .missing }
                if files.contains(url.path) { return .file }
                if packages.contains(url.path) { return .package }
                if links.contains(url.path) { return .symbolicLink }
                return .folder
            },
            isVolumeRoot: { volumes.contains($0.path) }))
    }

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test func protectedLocationsAreRefused() {
        let policy = policy()
        #expect(policy.evaluate(url("/"), existing: []) == .refuse(.volumeRoot(name: "/")))
        #expect(policy.evaluate(home, existing: []) == .refuse(.homeFolder))
        #expect(policy.evaluate(url("/Users/test/"), existing: []) == .refuse(.homeFolder))
        for name in VaporDropPolicy.standardHomeFolders {
            #expect(policy.evaluate(home.appendingPathComponent(name), existing: []) == .refuse(.standardFolder(name: name)))
        }
        for root in VaporDropPolicy.systemRoots {
            #expect(policy.evaluate(url(root), existing: []) == .refuse(.systemLocation(name: url(root).lastPathComponent)))
            #expect(policy.evaluate(url(root + "/Caches/thing"), existing: []) == .refuse(.systemLocation(name: "thing")))
        }
        #expect(policy.evaluate(url("/private/var/folders/xy/T/node_modules"), existing: [])
                == .refuse(.systemLocation(name: "node_modules")))
        #expect(policy.evaluate(url("/Users"), existing: []) == .refuse(.systemLocation(name: "Users")))
        #expect(policy.evaluate(url("/Volumes"), existing: []) == .refuse(.systemLocation(name: "Volumes")))
        // `..` can't climb out of the checks.
        #expect(policy.evaluate(url("/Users/test/dev/../Documents"), existing: []) == .refuse(.standardFolder(name: "Documents")))
        #expect(policy.evaluate(url("/Users/test/dev/../../test"), existing: []) == .refuse(.homeFolder))
    }

    @Test func credentialAndCloudFoldersAreRefused() {
        let policy = policy()
        // Folders directly in ~/Library, except the cache and log folders.
        for name in ["Keychains", "Mail", "Application Support", "Developer", "Mobile Documents", "CloudStorage"] {
            #expect(policy.evaluate(home.appendingPathComponent("Library/\(name)"), existing: []) == .refuse(.standardFolder(name: name)),
                    "\(name)")
        }
        // Keychains and the cloud-synced folders are protected with everything inside them.
        for path in ["Library/Keychains/ABC-123", "Library/Mobile Documents/com~apple~CloudDocs/app/node_modules",
                     "Library/CloudStorage/Dropbox/app/node_modules", "library/cloudstorage/Box/build"] {
            let folder = home.appendingPathComponent(path)
            #expect(policy.evaluate(folder, existing: []) == .refuse(.systemLocation(name: folder.lastPathComponent)), "\(path)")
        }
        // Credential and shell folders the uninstaller protects too.
        for name in [".ssh", ".gnupg", ".config", ".local", ".Trash", ".SSH"] {
            #expect(policy.evaluate(home.appendingPathComponent(name), existing: []) == .refuse(.standardFolder(name: name)), "\(name)")
        }
        // The cache and log folders can be rebuilt, so Vapor still takes them whole.
        for name in ["Caches", "Logs", "caches"] {
            let folder = home.appendingPathComponent("Library/\(name)")
            #expect(policy.evaluate(folder, existing: []) == .accept(url: folder, replacing: []), "\(name)")
        }
        // ~/.cache is a cache, so it stays allowed.
        let cache = home.appendingPathComponent(".cache")
        #expect(policy.evaluate(cache, existing: []) == .accept(url: cache, replacing: []))
        #expect(!VaporDropPolicy.protectedHomeItems.contains(".cache"))
        #expect(VaporDropPolicy.protectedHomeItems.isSubset(of: AppUninstallPathPolicy.protectedHomeItems))
    }

    @Test func subfoldersOfStandardFoldersAreAllowed() {
        let policy = policy()
        for path in ["Library/Caches/com.example", "Library/Developer/Xcode/DerivedData", "Documents/app/node_modules",
                     "Downloads/old/build", "Library/Application Support/Code/Cache", ".config/app/cache"] {
            let folder = home.appendingPathComponent(path)
            #expect(policy.evaluate(folder, existing: []) == .accept(url: folder, replacing: []), "\(path)")
        }
        // Another user's standard folder isn't one of this home's standard folders, but /Users itself is protected.
        let other = url("/Users/other/dev")
        #expect(policy.evaluate(other, existing: []) == .accept(url: other, replacing: []))
    }

    @Test func volumesFilesPackagesLinksAndMissingItems() {
        let policy = policy(files: ["/Users/test/dev/notes.txt"], packages: ["/Users/test/dev/Tool.app"],
                            links: ["/Users/test/dev/link"], missing: ["/Users/test/dev/gone"],
                            volumes: ["/Volumes/Backup"])
        #expect(policy.evaluate(url("/Volumes/Backup"), existing: []) == .refuse(.volumeRoot(name: "Backup")))
        #expect(policy.evaluate(url("/Users/test/dev/notes.txt"), existing: []) == .refuse(.notAFolder))
        #expect(policy.evaluate(url("/Users/test/dev/Tool.app"), existing: []) == .refuse(.package))
        #expect(policy.evaluate(url("/Users/test/dev/link"), existing: []) == .refuse(.notAFolder))
        #expect(policy.evaluate(url("/Users/test/dev/gone"), existing: []) == .refuse(.missing(name: "gone")))
        let onDisk = url("/Volumes/Backup/proj/node_modules")
        #expect(policy.evaluate(onDisk, existing: []) == .accept(url: onDisk, replacing: []))
    }

    @Test func duplicatesAndNestedFoldersAreRefused() {
        let policy = policy()
        let modules = url("/Users/test/dev/app/node_modules")
        #expect(policy.evaluate(modules, existing: [modules]) == .refuse(.alreadyAdded(name: "node_modules")))
        #expect(policy.evaluate(url("/Users/test/dev/app/node_modules/"), existing: [modules])
                == .refuse(.alreadyAdded(name: "node_modules")))
        #expect(policy.evaluate(modules.appendingPathComponent("react"), existing: [modules])
                == .refuse(.alreadyAdded(name: "react")))
        // A sibling whose name starts the same is not inside.
        let sibling = url("/Users/test/dev/app/node_modules_old")
        #expect(policy.evaluate(sibling, existing: [modules]) == .accept(url: sibling, replacing: []))
    }

    @Test func aParentReplacesTheFoldersInside() {
        let policy = policy()
        let app = url("/Users/test/dev/app")
        let modules = app.appendingPathComponent("node_modules")
        let next = app.appendingPathComponent(".next")
        let other = url("/Users/test/dev/site/dist")
        #expect(policy.evaluate(app, existing: [modules, other, next]) == .accept(url: app, replacing: [modules, next]))
    }

    @Test func oneDropKeepsOnlyTheOutermostFolder() {
        let policy = policy()
        let app = url("/Users/test/dev/app")
        let modules = app.appendingPathComponent("node_modules")
        #expect(policy.evaluate([modules, app], existing: [])
                == [.accept(url: modules, replacing: []), .accept(url: app, replacing: [modules])])
        #expect(policy.evaluate([app, modules], existing: [])
                == [.accept(url: app, replacing: []), .refuse(.alreadyAdded(name: "node_modules"))])
    }

    @Test func vaporsOwnStagingFoldersAreProtected() {
        var policy = policy()
        policy.stagingRoots = [url("/Users/test/Library/Caches/DOKK/Vapor/staging")]
        #expect(policy.evaluate(url("/Users/test/Library/Caches/DOKK/Vapor/staging/x"), existing: [])
                == .refuse(.systemLocation(name: "x")))
        #expect(policy.evaluate(url("/Volumes/Backup/.dokk-vapor"), existing: [])
                == .refuse(.systemLocation(name: ".dokk-vapor")))
        #expect(policy.evaluate(url("/Users/test/dev/.node_modules.dokk-vapor-1234"), existing: [])
                == .refuse(.systemLocation(name: ".node_modules.dokk-vapor-1234")))
    }

    @Test func liveInspectorTellsFoldersFilesPackagesAndLinksApart() throws {
        let temp = try VaporTempDirectory("vapor-inspector")
        let folder = try temp.folder("cache")
        let file = try temp.file("notes.txt")
        let app = try temp.folder("Tool.app/Contents")
            .deletingLastPathComponent()
        let link = temp.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        let inspector = VaporFileInspector.live
        #expect(inspector.kind(folder) == .folder)
        #expect(inspector.kind(file) == .file)
        #expect(inspector.kind(app) == .package)
        #expect(inspector.kind(link) == .symbolicLink)
        #expect(inspector.kind(temp.url.appendingPathComponent("missing")) == .missing)
        #expect(!inspector.isVolumeRoot(folder))
        #expect(inspector.isVolumeRoot(URL(fileURLWithPath: "/")))
    }

    @Test func aLinkedParentCannotReachAProtectedFolder() throws {
        let temp = try VaporTempDirectory("vapor-linked-parent")
        let home = try temp.folder("home")
        try temp.folder("home/Documents")
        try temp.folder("home/dev/node_modules")
        let alias = temp.url.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: home)
        // Temporary folders live under /private, a system location, so that list is emptied here.
        let policy = VaporDropPolicy(home: home, systemRoots: [])
        let throughLink = alias.appendingPathComponent("Documents")
        #expect(policy.evaluate(throughLink, existing: []) == .refuse(.standardFolder(name: "Documents")))
        #expect(policy.revalidate(throughLink) == .standardFolder(name: "Documents"))
        #expect(policy.evaluate(alias, existing: []) == .refuse(.notAFolder))
        // A cache reached through the same link is still fine.
        let cache = alias.appendingPathComponent("dev/node_modules")
        guard case .accept(let accepted, _) = policy.evaluate(cache, existing: []) else {
            Issue.record("a cache behind a linked parent was refused")
            return
        }
        #expect(accepted.path == cache.path)
    }
}
