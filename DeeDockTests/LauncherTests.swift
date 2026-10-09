import AppKit
import Testing
@testable import DeeDock

@MainActor
struct LauncherTests {
    @Test("App search handles accents, initials, aliases, and a transposed typo", arguments: ["pixel", "PIXÉL", "ps", "pixel studio", "pixle", "editor"])
    func searchAliases(_ query: String) {
        let app = LauncherApplication(reference: ApplicationReference(bundleIdentifier: "example.pixel",
            url: URL(fileURLWithPath: "/Applications/Pixel.app"), name: "Pixél Studio"), aliases: ["Editor"])
        #expect(app.score(LauncherApplication.normalize(query)) != nil)
    }

    @Test("Invisible formatting does not prevent localized app-name searches")
    func invisibleFormatting() {
        #expect(LauncherApplication.normalize("System\u{00ad}einstellungen") == "systemeinstellungen")
    }

    @Test("General discovery excludes helpers and caches while retaining user apps")
    func discoveryLocations() {
        let home = URL(fileURLWithPath: "/Users/example")
        for path in ["/Applications/Host.app/Contents/Helpers/Child.app", "/Users/example/Library/Caches/Cache.app", "/Users/example/.Trash/Old.app", "/System/Library/PrivateFrameworks/Helper.app"] {
            #expect(!LauncherDiscovery.isUserFacingLocation(URL(fileURLWithPath: path), home: home))
        }
        for path in ["/Applications/Editor.app", "/Users/example/Projects/Build/Editor.app", "/System/Applications/Calculator.app", "/System/Library/CoreServices/Finder.app"] {
            #expect(LauncherDiscovery.isUserFacingLocation(URL(fileURLWithPath: path), home: home))
        }
    }

    @Test("Applications folders keep /Applications and ~/Applications", arguments: [
        "/Applications/Safari.app",
        "/Applications/Utilities/Terminal.app",
        "/Users/example/Applications/Pixel.app",
        "/APPLICATIONS/Notes.app",
        "/System/Volumes/Data/Applications/Mail.app",
        "/System/Volumes/Data/Users/example/Applications/Tools.app",
    ])
    func applicationsFolderIncludes(_ path: String) {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(LauncherLocationFilter.applicationsFolders.includes(URL(fileURLWithPath: path), home: home))
    }

    @Test("Applications folders hide system apps and project builds", arguments: [
        "/System/Applications/Calculator.app",
        "/System/Library/CoreServices/Finder.app",
        "/System/Library/CoreServices/Applications/Feedback Assistant.app",
        "/Users/example/Projects/Build/Editor.app",
        "/opt/homebrew/Cellar/python/python.app",
        "/ApplicationsExtra/Foo.app",
        "/Users/example/Applications Extra/Foo.app",
    ])
    func applicationsFolderExcludes(_ path: String) {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(!LauncherLocationFilter.applicationsFolders.includes(URL(fileURLWithPath: path), home: home))
    }

    @Test("Apps below another app's folder are nested; siblings and top-level folders are not")
    func nestedApplications() {
        let home = URL(fileURLWithPath: "/Users/example")
        let editor = "/Applications/Unity/Hub/Editor/6000.6.0f1"
        let paths = [
            "\(editor)/Unity.app",
            "\(editor)/Unity Bug Reporter.app",
            "\(editor)/PlaybackEngines/MacStandaloneSupport/Variations/macos_arm64_mono/UnityPlayer.app",
            "/Applications/Safari.app",
            "/Applications/Utilities/Terminal.app",
            "/Users/example/Projects/Tool.app",
            "/Users/example/Projects/Build/Products/Editor.app",
        ]
        let urls = paths.map { URL(fileURLWithPath: $0) }
        let nested = LauncherDiscovery.nestedURLs(urls, home: home).map(\.path)
        #expect(nested == ["\(editor)/PlaybackEngines/MacStandaloneSupport/Variations/macos_arm64_mono/UnityPlayer.app"])
    }

    @Test("A top-level copy wins over a nested copy with the same id, whichever comes first", arguments: [false, true])
    func deduplicationPrefersTopLevelCopy(nestedFirst: Bool) {
        func copy(_ path: String, nested: Bool) -> LauncherApplication {
            LauncherApplication(reference: ApplicationReference(bundleIdentifier: "example.tool",
                url: URL(fileURLWithPath: path), name: "Tool"), isNested: nested)
        }
        let nested = copy("/Applications/Vendor/Bundled/Tool.app", nested: true)
        let topLevel = copy("/Users/example/Applications/Tool.app", nested: false)
        let kept = LauncherDiscovery.deduplicated(nestedFirst ? [nested, topLevel] : [topLevel, nested])
        #expect(kept == [topLevel])
    }

    @Test("Among copies with the same nesting, the first in scan order wins")
    func deduplicationKeepsFirstPeer() {
        let paths = ["/Applications/Tool.app", "/Users/example/Applications/Tool.app"]
        let copies = paths.map {
            LauncherApplication(reference: ApplicationReference(bundleIdentifier: "example.tool",
                url: URL(fileURLWithPath: $0), name: "Tool"))
        }
        #expect(LauncherDiscovery.deduplicated(copies).map(\.reference.url.path) == ["/Applications/Tool.app"])
    }

    @Test("Standard Mac locations add /System/Applications only", arguments: [
        "/Applications/Safari.app",
        "/Users/example/Applications/Pixel.app",
        "/System/Applications/Calculator.app",
        "/System/Applications/Utilities/Terminal.app",
        "/System/Volumes/Data/Applications/Mail.app",
    ])
    func standardMacLocationsInclude(_ path: String) {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(LauncherLocationFilter.standardMacLocations.includes(URL(fileURLWithPath: path), home: home))
    }

    @Test("Standard Mac locations still hide CoreServices and project builds", arguments: [
        "/System/Library/CoreServices/Finder.app",
        "/System/Library/CoreServices/Applications/Feedback Assistant.app",
        "/Users/example/Projects/Build/Editor.app",
        "/opt/homebrew/Cellar/python/python.app",
    ])
    func standardMacLocationsExclude(_ path: String) {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(!LauncherLocationFilter.standardMacLocations.includes(URL(fileURLWithPath: path), home: home))
    }

    @Test("All locations keep discovered junk")
    func allLocationsIncludeProjectBuilds() {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(LauncherLocationFilter.all.includes(
            URL(fileURLWithPath: "/Users/example/Projects/Build/DevenvCreator.app"), home: home))
    }

    @Test("Browse scroll identity includes the location filter even when sections match")
    func browseScrollContextIncludesLocation() {
        let catalog = ApplicationCatalog(
            service: ApplicationService(),
            launcherLibrary: LauncherLibrary(applications: [])
        )
        let state = LauncherState(catalog: catalog)
        let applications = LauncherBrowseScroll.Context(state: state, columns: 4, groups: [])
        state.locationFilter = .all
        let allLocations = LauncherBrowseScroll.Context(state: state, columns: 4, groups: [])
        #expect(applications != allLocations)
        #expect(applications.locationFilter == .applicationsFolders)
        #expect(allLocations.locationFilter == .all)
    }

    @Test("Location filter composes with the All apps / Recent filter")
    func locationFilterComposesWithAppFilter() {
        func app(_ id: String, _ path: String) -> LauncherApplication {
            LauncherApplication(reference: ApplicationReference(
                bundleIdentifier: id, url: URL(fileURLWithPath: path), name: id))
        }
        let safari = app("safari", "/Applications/Safari.app")
        let calculator = app("calculator", "/System/Applications/Calculator.app")
        let python = app("python", "/opt/homebrew/Cellar/python/python.app")
        let catalog = ApplicationCatalog(
            service: ApplicationService(),
            launcherLibrary: LauncherLibrary(applications: [safari, calculator, python])
        )
        let state = LauncherState(catalog: catalog)
        #expect(state.results.map(\.id) == [safari.id])
        state.locationFilter = .standardMacLocations
        #expect(Set(state.results.map(\.id)) == [safari.id, calculator.id])
        state.locationFilter = .all
        #expect(Set(state.results.map(\.id)) == [safari.id, calculator.id, python.id])
        catalog.launcherHistory.record(python.reference)
        state.filter = .recent
        #expect(state.results.map(\.id) == [python.id])
        state.locationFilter = .applicationsFolders
        #expect(state.results.isEmpty)
    }

    @Test("An exact app name outranks a prefix; unrelated words do not become fuzzy hits")
    func relevance() throws {
        let app = LauncherApplication(reference: ApplicationReference(bundleIdentifier: "example.notes",
            url: URL(fileURLWithPath: "/Applications/Notes.app"), name: "Notes"))
        let exact = try #require(app.score("notes"))
        let prefix = try #require(app.score("note"))
        #expect(exact < prefix)
        #expect(app.score("music") == nil)
        #expect(app.score("notes music") == nil)
    }

    @Test("History persists successful opens, survives restart, and clears explicitly")
    func history() throws {
        let name = "LauncherTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let app = ApplicationReference(bundleIdentifier: "example.app", url: URL(fileURLWithPath: "/Example.app"), name: "Example")
        let history = LauncherHistory(defaults: defaults)
        history.record(app); history.record(app)
        let restored = LauncherHistory(defaults: defaults)
        #expect(restored.visits[app.id]?.count == 2)
        restored.clear()
        #expect(LauncherHistory(defaults: defaults).visits.isEmpty)
    }

    @Test("Unreadable history bytes survive until the user explicitly clears history")
    func unreadableHistory() throws {
        let name = "LauncherTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let corrupt = Data("not a history document".utf8)
        defaults.set(corrupt, forKey: "launcher.history.v1")
        let history = LauncherHistory(defaults: defaults)
        history.record(ApplicationReference(bundleIdentifier: nil, url: URL(fileURLWithPath: "/Example.app"), name: "Example"))
        #expect(history.unreadable)
        #expect(defaults.data(forKey: "launcher.history.v1") == corrupt)
        history.clear()
        #expect(!history.unreadable)
    }
}
