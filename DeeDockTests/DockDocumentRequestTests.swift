import AppKit
import Testing

@MainActor
struct DockDocumentRequestTests {
    @Test("Every batch reaches an app even while an ordinary launch and another batch are pending")
    func repeatedDrops() async {
        let service = DocumentFixtureService()
        let catalog = ApplicationCatalog(service: service)
        let app = DisplayFixtures.app("editor")
        catalog.open(app) { _ in }
        await service.waitForRequests(1)
        let first = URL(fileURLWithPath: "/fixture/first.txt")
        let second = URL(fileURLWithPath: "/fixture/second.txt")
        var completions = 0
        catalog.openDocuments(DocumentResourceAccess([first]), with: app) { _ in completions += 1 }
        catalog.openDocuments(DocumentResourceAccess([second]), with: app) { _ in completions += 1 }
        await service.waitForRequests(3)
        #expect(service.requests.filter { $0.urls != nil }.count == 2)
        #expect(Set(service.requests.compactMap { $0.urls?.first }) == [first, second])
        #expect(catalog.documentRequests.count == 2)
        service.finishAll()
        await service.waitForReturns(3)
        #expect(completions == 2)
        #expect(catalog.busyApplications.isEmpty)
        catalog.stop()
    }

    @Test("Removing the initiating display preserves delivery and leases but suppresses its error")
    func disconnectedDisplay() async {
        let service = DocumentFixtureService()
        let catalog = ApplicationCatalog(service: service)
        let dock = makeDock(catalog)
        let reference = dock.items[0].reference
        var access: DocumentResourceAccess? = DocumentResourceAccess([URL(fileURLWithPath: "/fixture/document")])
        weak var lease = access
        dock.openDocuments(access!, with: reference)
        access = nil
        await service.waitForRequests(1)
        dock.stop()
        #expect(lease != nil)
        #expect(catalog.documentRequests.count == 1)
        service.finishAll()
        await service.waitForReturns(1)
        #expect(dock.errorMessage == nil)
        #expect(service.cancelled == [false])
        #expect(catalog.documentRequests.isEmpty)
        #expect(lease == nil)
        lease = nil
        catalog.stop()
    }

    @Test("Shutdown cancels document tasks and ignores late OS completion")
    func shutdown() async {
        let service = DocumentFixtureService()
        let catalog = ApplicationCatalog(service: service)
        var delivered = false
        catalog.openDocuments(DocumentResourceAccess([URL(fileURLWithPath: "/fixture/document")]), with: DisplayFixtures.app("app")) { _ in delivered = true }
        await service.waitForRequests(1)
        catalog.stop()
        #expect(catalog.documentRequests.isEmpty)
        service.finishAll()
        await service.waitForReturns(1)
        #expect(service.cancelled == [true])
        #expect(!delivered)
    }

    @Test("Spring-loading sends no documents and ignores failure after the pointer leaves")
    func springActivation() async {
        let service = DocumentFixtureService()
        let catalog = ApplicationCatalog(service: service)
        let dock = makeDock(catalog)
        var current = true
        dock.springOpen(dock.items[0]) { current }
        await service.waitForRequests(1)
        #expect(service.requests[0].urls == nil)
        #expect(catalog.documentRequests.isEmpty)
        current = false
        service.finishAll()
        await service.waitForReturns(1)
        #expect(dock.errorMessage == nil)
        dock.stop(); catalog.stop()
    }

    @Test("A live dock receives the file-opening failure")
    func failure() async {
        let service = DocumentFixtureService()
        let catalog = ApplicationCatalog(service: service)
        let dock = makeDock(catalog)
        dock.openDocuments(DocumentResourceAccess([URL(fileURLWithPath: "/fixture/document")]), with: dock.items[0].reference)
        await service.waitForRequests(1)
        service.finishAll()
        await service.waitForReturns(1)
        #expect(dock.errorMessage != nil)
        dock.stop(); catalog.stop()
    }

    @Test("An expired spring visit never submits an application request")
    func expiredSpringActivation() async {
        let service = DocumentFixtureService()
        let catalog = ApplicationCatalog(service: service)
        let dock = makeDock(catalog)
        dock.springOpen(dock.items[0]) { false }
        #expect(service.requests.isEmpty && catalog.busyApplications.isEmpty)
        dock.stop(); catalog.stop()
    }

    private func makeDock(_ catalog: ApplicationCatalog) -> DockStore {
        let profiles = DisplayProfilesStore(defaults: DockSettingsStore(repository: nil), repository: nil)
        let display = DisplayFixtures.screen("primary", runtimeID: 1, primary: true)
        profiles.synchronize([display]) { [DisplayFixtures.app("app")] }
        return DockStore(displayID: display.id, catalog: catalog, profiles: profiles)
    }
}

/// Each request waits for explicit completion. No workspace APIs, wall-clock waits, or real apps.
@MainActor
private final class DocumentFixtureService: ApplicationServicing {
    struct Request { let reference: ApplicationReference; let urls: [URL]? }
    var requests: [Request] = []
    var cancelled: [Bool] = []
    private var pending: [CheckedContinuation<Void, any Error>] = []
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var returnWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func runningApplications() -> [ApplicationReference] { [] }
    func defaultFavorites() -> [ApplicationReference] { [] }
    func resolvedURL(for reference: ApplicationReference) -> URL? { reference.url }
    func icon(for url: URL?) -> NSImage { NSImage(size: NSSize(width: 48, height: 48)) }
    func pruneIcons(keeping urls: Set<URL>) {}
    func performPrimaryAction(_ reference: ApplicationReference) async throws { try await request(reference, urls: nil) }
    func open(_ reference: ApplicationReference) async throws { try await request(reference, urls: nil) }
    func openDocuments(_ urls: [URL], with reference: ApplicationReference) async throws { try await request(reference, urls: urls) }

    private func request(_ reference: ApplicationReference, urls: [URL]?) async throws {
        defer {
            cancelled.append(Task.isCancelled)
            let ready = returnWaiters.filter { $0.0 <= cancelled.count }
            returnWaiters.removeAll { $0.0 <= cancelled.count }
            ready.forEach { $0.1.resume() }
        }
        try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            requests.append(Request(reference: reference, urls: urls))
            let ready = requestWaiters.filter { $0.0 <= requests.count }
            requestWaiters.removeAll { $0.0 <= requests.count }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitForRequests(_ count: Int) async {
        if requests.count < count { await withCheckedContinuation { requestWaiters.append((count, $0)) } }
    }
    func waitForReturns(_ count: Int) async {
        if cancelled.count < count { await withCheckedContinuation { returnWaiters.append((count, $0)) } }
    }
    func finishAll() {
        let current = pending; pending = []
        current.forEach { $0.resume(throwing: CocoaError(.fileReadNoPermission)) }
    }
}
