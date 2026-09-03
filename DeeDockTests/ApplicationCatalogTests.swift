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
        dock.performPrimaryAction(dock.items[0])
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

    @Test("App-icon action stays separate from explicit Open")
    func primaryActionRouting() async {
        let service = ControlledApplicationService()
        let catalog = ApplicationCatalog(service: service)
        let reference = DisplayFixtures.app("app")

        catalog.performPrimaryAction(reference) { error in #expect(error == nil) }
        await service.waitForRequest()
        #expect(service.primaryRequests == 1)
        #expect(service.openRequests == 0)
        service.finishSuccessfully()
        await service.waitForReturn()
        await Task.yield()

        catalog.open(reference) { error in #expect(error == nil) }
        await service.waitForRequest(count: 2)
        #expect(service.primaryRequests == 1)
        #expect(service.openRequests == 1)
        service.finishSuccessfully()
        await service.waitForReturn(count: 2)
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
    var primaryRequests = 0
    var openRequests = 0
    var requests: Int { primaryRequests + openRequests }
    var wasCancelled = false
    private var pending: CheckedContinuation<Void, any Error>?
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var returnWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var returns = 0
    func runningApplications() -> [ApplicationReference] { [] }
    func defaultFavorites() -> [ApplicationReference] { [] }
    func resolvedURL(for reference: ApplicationReference) -> URL? { reference.url }
    func icon(for url: URL?) -> NSImage { NSImage(size: NSSize(width: 48, height: 48)) }
    func pruneIcons(keeping urls: Set<URL>) {}
    func openDocuments(_ urls: [URL], with reference: ApplicationReference) async throws { Issue.record("Unexpected document open") }
    func performPrimaryAction(_ reference: ApplicationReference) async throws {
        primaryRequests += 1
        resumeRequestWaiters()
        try await request()
    }
    func open(_ reference: ApplicationReference) async throws {
        openRequests += 1
        resumeRequestWaiters()
        try await request()
    }
    private func request() async throws {
        defer {
            wasCancelled = Task.isCancelled
            returns += 1
            let ready = returnWaiters.filter { $0.0 <= returns }
            returnWaiters.removeAll { $0.0 <= returns }
            ready.forEach { $0.1.resume() }
        }
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
        }
    }
    func waitForRequest() async {
        await waitForRequest(count: 1)
    }
    func waitForRequest(count: Int) async {
        if requests < count { await withCheckedContinuation { requestWaiters.append((count, $0)) } }
    }
    func finish() { pending?.resume(throwing: CocoaError(.fileNoSuchFile)); pending = nil }
    func finishSuccessfully() { pending?.resume(); pending = nil }
    func waitForReturn() async {
        await waitForReturn(count: 1)
    }
    func waitForReturn(count: Int) async {
        if returns < count { await withCheckedContinuation { returnWaiters.append((count, $0)) } }
    }
    private func resumeRequestWaiters() {
        let ready = requestWaiters.filter { $0.0 <= requests }
        requestWaiters.removeAll { $0.0 <= requests }
        ready.forEach { $0.1.resume() }
    }
}
