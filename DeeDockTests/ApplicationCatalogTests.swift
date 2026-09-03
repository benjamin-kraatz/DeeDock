import AppKit
import Testing

@MainActor
struct ApplicationCatalogTests {
    @Test("Removing a dock preserves a shared launch but refuses its stale error")
    func disconnectedLaunch() async {
        let service = ControlledApplicationService()
        let catalog = ApplicationCatalog(service: service)
        let profiles = DisplayProfilesStore(defaults: DockSettingsStore(repository: nil), repository: nil)
        let display = DisplayFixtures.screen("primary", runtimeID: 1, primary: true)
        let reference = DisplayFixtures.app("app")
        profiles.synchronize([display]) { [reference] }
        let dock = DockStore(displayID: display.id, catalog: catalog, profiles: profiles)
        dock.open(dock.items[0])
        await service.waitForRequest()
        catalog.open(reference) { _ in Issue.record("A duplicate request must not be submitted") }
        #expect(service.requests == 1)
        #expect(catalog.launching == [reference.id])
        dock.stop()
        #expect(catalog.launching == [reference.id])
        service.finish()
        await service.waitForReturn()
        await Task.yield()
        #expect(dock.errorMessage == nil)
        #expect(catalog.launching.isEmpty)
        #expect(!service.wasCancelled)
        catalog.stop()
    }

    @Test("Quitting cancels pending work and ignores late completion")
    func shutdown() async {
        let service = ControlledApplicationService()
        let catalog = ApplicationCatalog(service: service)
        var delivered = false
        catalog.open(DisplayFixtures.app("app")) { _ in delivered = true }
        await service.waitForRequest()
        catalog.stop()
        #expect(catalog.launching.isEmpty)
        service.finish()
        await service.waitForReturn()
        await Task.yield()
        #expect(!delivered)
        #expect(service.wasCancelled)
    }
}

/// A manually completed launch: no NSWorkspace access, live icons, timers, or real apps.
@MainActor
private final class ControlledApplicationService: ApplicationServicing {
    var requests = 0
    var wasCancelled = false
    private var pending: CheckedContinuation<Void, any Error>?
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var returnWaiter: CheckedContinuation<Void, Never>?
    private var returned = false
    func runningApplications() -> [ApplicationReference] { [] }
    func defaultFavorites() -> [ApplicationReference] { [] }
    func resolvedURL(for reference: ApplicationReference) -> URL? { reference.url }
    func icon(for url: URL?) -> NSImage { NSImage(size: NSSize(width: 48, height: 48)) }
    func pruneIcons(keeping urls: Set<URL>) {}
    func openDocuments(_ urls: [URL], with reference: ApplicationReference) async throws { Issue.record("Unexpected document open") }
    func open(_ reference: ApplicationReference) async throws {
        requests += 1
        defer {
            wasCancelled = Task.isCancelled
            returned = true
            returnWaiter?.resume()
            returnWaiter = nil
        }
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            requestWaiter?.resume()
            requestWaiter = nil
        }
    }
    func waitForRequest() async {
        if requests == 0 { await withCheckedContinuation { requestWaiter = $0 } }
    }
    func finish() { pending?.resume(throwing: CocoaError(.fileNoSuchFile)); pending = nil }
    func waitForReturn() async {
        if !returned { await withCheckedContinuation { returnWaiter = $0 } }
    }
}
