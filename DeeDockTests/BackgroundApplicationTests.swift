import AppKit
import Darwin
import Testing
@testable import DeeDock

/// Running in Background as the catalog and dock see it. Records are fed through the catalog's
/// test seam, so no test reads Launch Services or signals a real app.
@MainActor
struct BackgroundApplicationCatalogTests {
    @Test("An app with a regular running instance is never also listed as running in background")
    func runningInstanceWins() {
        let service = BackgroundFixtureService(running: [DisplayFixtures.app("alpha")])
        let catalog = ApplicationCatalog(service: service)
        catalog.setBackgroundApplicationsForTesting([Self.record("alpha"), Self.record("bravo")])

        #expect(catalog.running.map(\.id) == ["alpha"])
        #expect(catalog.background.map(\.id) == ["bravo"])
        // The Launcher, Hub, and suggestions keep seeing regular processes only.
        #expect(catalog.runningIDs == ["alpha"])
        #expect(catalog.dockOrderIDs == ["alpha", "bravo"])
        #expect(catalog.isRunningInBackground(DisplayFixtures.app("bravo")))
        #expect(!catalog.isRunningInBackground(DisplayFixtures.app("alpha")))
        catalog.stop()
    }

    @Test("A tile keeps its place while its app moves from running to background and back")
    func positionContinuity() throws {
        let apps = ["alpha", "bravo", "charlie"].map(DisplayFixtures.app)
        let service = BackgroundFixtureService(running: apps)
        let catalog = ApplicationCatalog(service: service)
        catalog.refresh()
        let dock = Self.dock(catalog: catalog, pins: [])
        #expect(dock.items.map(\.id) == ["alpha", "bravo", "charlie"])

        // Bravo quits while its helpers keep running; both changes publish together.
        service.running = [apps[0], apps[2]]
        catalog.setBackgroundApplicationsForTesting([Self.record("bravo")])
        dock.refresh()
        #expect(dock.items.map(\.id) == ["alpha", "bravo", "charlie"])
        let background = try #require(dock.items.first { $0.id == "bravo" })
        #expect(background.isRunningInBackground)
        #expect(!background.isRunning)
        #expect(background.runningState == .background)
        #expect(catalog.runningIDs == ["alpha", "charlie"])

        // Reopened: the regular instance takes over in the same slot.
        service.running = apps
        catalog.setBackgroundApplicationsForTesting([])
        dock.refresh()
        #expect(dock.items.map(\.id) == ["alpha", "bravo", "charlie"])
        #expect(dock.items.allSatisfy { $0.isRunning && !$0.isRunningInBackground })
        dock.stop()
        catalog.stop()
    }

    @Test("When the last background process ends, an unpinned tile leaves and a pinned tile clears its state")
    func backgroundEnds() throws {
        let service = BackgroundFixtureService(running: [])
        let catalog = ApplicationCatalog(service: service)
        catalog.setBackgroundApplicationsForTesting([Self.record("pinned"), Self.record("loose")])
        let dock = Self.dock(catalog: catalog, pins: [DisplayFixtures.app("pinned")])

        #expect(dock.items.map(\.id) == ["pinned", "loose"])
        let pinned = try #require(dock.items.first)
        #expect(pinned.isFavorite && pinned.isRunningInBackground && !pinned.isRunning)
        let loose = try #require(dock.items.last)
        #expect(!loose.isFavorite && loose.isRunningInBackground)

        catalog.setBackgroundApplicationsForTesting([])
        dock.refresh()
        #expect(dock.items.map(\.id) == ["pinned"])
        #expect(dock.items.first?.runningState == .notRunning)
        dock.stop()
        catalog.stop()
    }

    @Test("A tile is never both running and running in background")
    func neverBoth() throws {
        let service = BackgroundFixtureService(running: [DisplayFixtures.app("pinned")])
        let catalog = ApplicationCatalog(service: service)
        catalog.setBackgroundApplicationsForTesting([Self.record("pinned")])
        let dock = Self.dock(catalog: catalog, pins: [DisplayFixtures.app("pinned")])

        let item = try #require(dock.items.first)
        #expect(item.isRunning)
        #expect(!item.isRunningInBackground)
        #expect(item.runningState == .running)
        dock.stop()
        catalog.stop()
    }

    @Test("Section visibility treats an unpinned background tile as a running app")
    func sectionGroup() {
        let catalog = ApplicationCatalog(service: BackgroundFixtureService(running: []))
        catalog.setBackgroundApplicationsForTesting([Self.record("loose")])
        let dock = Self.dock(catalog: catalog, pins: [DisplayFixtures.app("pinned")])

        let shown = DockSectionProjection.entries(items: dock.items, visibility: .showAll, expanded: false)
        #expect(shown.first { $0.item?.id == "loose" }?.appGroup == .running)
        let hidden = DockSectionProjection.entries(items: dock.items, visibility: .hideRunning, expanded: false)
        #expect(!hidden.contains { $0.item?.id == "loose" })
        dock.stop()
        catalog.stop()
    }

    @Test("A filtered secondary dock drops a background app, like a running app without windows")
    func secondaryDisplayFilter() {
        let catalog = ApplicationCatalog(service: BackgroundFixtureService(running: [DisplayFixtures.app("alpha")]))
        catalog.setBackgroundApplicationsForTesting([Self.record("bravo")])
        let dock = Self.dock(catalog: catalog, pins: [])
        dock.visibleApplicationIDs = []
        dock.refresh()
        #expect(dock.items.isEmpty)
        dock.stop()
        catalog.stop()
    }

    @Test("Stop is not requested for an app that is not running in background")
    func stopWithoutRecord() {
        let catalog = ApplicationCatalog(service: BackgroundFixtureService(running: [DisplayFixtures.app("alpha")]))
        catalog.setBackgroundApplicationsForTesting([Self.record("alpha")])
        // Running wins, so there is nothing to stop; neither is an unknown app.
        #expect(!catalog.stopRunningInBackground(DisplayFixtures.app("alpha")))
        #expect(!catalog.stopRunningInBackground(DisplayFixtures.app("unknown")))
        catalog.stop()
    }

    /// A record for `DisplayFixtures.app(id)`. The catalog never inspects its processes.
    private static func record(_ id: String) -> BackgroundApplication {
        let reference = DisplayFixtures.app(id)
        return BackgroundApplication(bundleURL: reference.url.standardizedFileURL, bundleIdentifier: id,
                                     name: reference.name, processes: [])
    }

    private static func dock(catalog: ApplicationCatalog, pins: [ApplicationReference]) -> DockStore {
        let profiles = DisplayProfilesStore(defaults: DockSettingsStore(repository: nil), repository: nil)
        let display = DisplayFixtures.screen("primary", runtimeID: 1, primary: true)
        profiles.synchronize([display]) { pins }
        return DockStore(displayID: display.id, catalog: catalog, profiles: profiles)
    }
}

/// The identity that keeps the stop action from signalling a reused PID.
struct BackgroundProcessIdentityTests {
    @Test("PID 0, launchd, and DOKK itself never get an identity", arguments: [pid_t(0), 1, getpid()])
    func refusedProcesses(pid: pid_t) {
        #expect(BackgroundProcess(pid: pid) == nil)
    }

    @Test("A live child gets an identity that stops matching once it exits")
    func childLifecycle() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }

        let identity = try #require(BackgroundProcess(pid: child.processIdentifier))
        #expect(identity.pid == child.processIdentifier)
        #expect(identity.isStillRunning)

        child.terminate()
        child.waitUntilExit()
        #expect(!identity.isStillRunning)
        #expect(!identity.send(SIGTERM))
    }
}

/// Running apps under test control; never launches, opens, or toggles anything.
@MainActor
private final class BackgroundFixtureService: ApplicationServicing {
    var running: [ApplicationReference]
    init(running: [ApplicationReference]) { self.running = running }
    func runningApplications() -> [ApplicationReference] { running }
    func defaultFavorites() -> [ApplicationReference] { [] }
    func resolvedURL(for reference: ApplicationReference) -> URL? { reference.url }
    func icon(for url: URL?) -> NSImage { NSImage(size: CGSize(width: 48, height: 48)) }
    func pruneIcons(keeping urls: Set<URL>) {}
    func openDocuments(_ urls: [URL], with reference: ApplicationReference) async throws { Issue.record("Unexpected document open") }
    func performPrimaryAction(_ reference: ApplicationReference) async throws -> ApplicationPrimaryActionOutcome {
        Issue.record("Background tests must never toggle applications")
        return .opened
    }
    func open(_ reference: ApplicationReference) async throws { Issue.record("Background tests must never launch applications") }
}
