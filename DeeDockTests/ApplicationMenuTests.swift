import AppKit
import Testing

@MainActor
struct ApplicationMenuTests {
    @Test("Permission checks remain read-only until the explicit enable action")
    func explicitPermissionRequest() {
        let service = StubWindowAccessService(status: .notEnabled)
        let controller = WindowAccessController(service: service)

        controller.refresh()
        #expect(service.requests == 0)
        #expect(controller.status == .notEnabled)

        controller.requestAccess()
        #expect(service.requests == 1)
        controller.openSystemSettings()
        #expect(service.settingsOpens == 1)
    }

    @Test("Window titles preserve order and duplicate identity while replacing blank titles")
    func windowTitleProjection() {
        let sessionID = UUID()
        let windows = [
            window(" Report ", sessionID: sessionID),
            window("Report", sessionID: sessionID, minimized: true),
            window(nil, sessionID: sessionID, main: true),
            window("  \n", sessionID: sessionID),
        ]

        #expect(ApplicationContextMenuProjection.windowTitles(windows, untitled: "Untitled") == [
            " Report ", "Report", "Untitled", "Untitled",
        ])
        #expect(Set(windows.map(\.token)).count == windows.count)
        #expect(windows[1].isMinimized)
        #expect(windows[2].isMain)
    }

    @Test("Snapshots distinguish permission, running, and aggregate hidden state")
    func snapshotStates() {
        let accessService = StubWindowAccessService(status: .notEnabled)
        let access = WindowAccessController(service: accessService)
        let applications = StubApplicationMenuService()
        let controller = ApplicationMenuController(
            access: access,
            applications: applications,
            windows: StubApplicationWindowService()
        )
        let item = dockItem(running: true, available: true)

        #expect(controller.snapshot(for: item).windowState == .hidden)

        accessService.status = .unavailable
        #expect(controller.snapshot(for: item).windowState == .hidden)

        accessService.status = .enabled
        applications.processSnapshots = [
            ApplicationProcessSnapshot(processIdentifier: 41, isHidden: true, isActive: false),
            ApplicationProcessSnapshot(processIdentifier: 42, isHidden: true, isActive: false),
        ]
        let hidden = controller.snapshot(for: item)
        #expect(hidden.windowState == .loading)
        #expect(hidden.isRunning)
        #expect(hidden.allProcessesHidden)

        applications.processSnapshots[1] = ApplicationProcessSnapshot(
            processIdentifier: 42,
            isHidden: false,
            isActive: true
        )
        #expect(!controller.snapshot(for: item).allProcessesHidden)

        applications.processSnapshots = []
        let closed = controller.snapshot(for: item)
        #expect(!closed.isRunning)
        #expect(!closed.allProcessesHidden)
        #expect(closed.windowState == .hidden)
        controller.stop()
    }

    @Test("Application actions preserve group order and current hidden-state command")
    func actionProjection() {
        let visible = ApplicationMenuSnapshot(
            processes: [ApplicationProcessSnapshot(processIdentifier: 1, isHidden: false, isActive: true)],
            windowState: .hidden
        )
        #expect(ApplicationContextMenuProjection.applicationActions(isAvailable: true, snapshot: visible) == [
            .showInFinder, .setHidden(true), .bringAllToFront, .quit,
        ])

        let hidden = ApplicationMenuSnapshot(
            processes: [
                ApplicationProcessSnapshot(processIdentifier: 1, isHidden: true, isActive: false),
                ApplicationProcessSnapshot(processIdentifier: 2, isHidden: true, isActive: false),
            ],
            windowState: .loading
        )
        #expect(ApplicationContextMenuProjection.applicationActions(isAvailable: false, snapshot: hidden) == [
            .setHidden(false), .bringAllToFront, .quit,
        ])

        let closed = ApplicationMenuSnapshot(processes: [], windowState: .hidden)
        #expect(ApplicationContextMenuProjection.applicationActions(isAvailable: true, snapshot: closed) == [.showInFinder])
        #expect(ApplicationContextMenuProjection.applicationActions(isAvailable: false, snapshot: closed).isEmpty)
    }

    @Test("Discovery returns empty, populated, and unavailable menu states")
    func discoveryStates() async {
        let access = WindowAccessController(service: StubWindowAccessService(status: .enabled))
        let applications = StubApplicationMenuService()
        applications.processSnapshots = [ApplicationProcessSnapshot(
            processIdentifier: 51,
            isHidden: false,
            isActive: true
        )]
        let windows = StubApplicationWindowService()
        let controller = ApplicationMenuController(access: access, applications: applications, windows: windows)
        let item = dockItem(running: true, available: true)
        let snapshot = controller.snapshot(for: item)

        let emptyState = await discover(controller, item: item, snapshot: snapshot)
        #expect(emptyState == .loaded([]))

        let expected = window("Main", sessionID: UUID(), main: true)
        await windows.setDiscoveryResult(.success([expected]))
        let populatedState = await discover(controller, item: item, snapshot: snapshot)
        guard case .loaded(let discovered) = populatedState else {
            Issue.record("Expected populated windows")
            return
        }
        #expect(discovered.map(\.title) == ["Main"])

        await windows.setDiscoveryResult(.failure(.accessibility(-25204)))
        let unavailableState = await discover(controller, item: item, snapshot: snapshot)
        #expect(unavailableState == .unavailable(.accessibility(-25204)))
        controller.stop()
    }

    @Test("Cancellation rejects a late discovery result and discards its session")
    func staleDiscovery() async throws {
        let access = WindowAccessController(service: StubWindowAccessService(status: .enabled))
        let applications = StubApplicationMenuService()
        applications.processSnapshots = [ApplicationProcessSnapshot(
            processIdentifier: 61,
            isHidden: false,
            isActive: false
        )]
        let windows = StubApplicationWindowService(delay: .milliseconds(100))
        let controller = ApplicationMenuController(access: access, applications: applications, windows: windows)
        let item = dockItem(running: true, available: true)
        var delivered = false

        let sessionID = try #require(controller.beginDiscovery(for: item, snapshot: controller.snapshot(for: item)) { _ in
            delivered = true
        })
        controller.cancelDiscovery(sessionID)
        await Task.yield()

        #expect(!delivered)
        #expect(await windows.discardedSessions().contains(sessionID))
        controller.stop()
    }

    @Test("Window actions preserve exact tokens and reject stale or vanished windows")
    func windowActionRouting() async {
        let access = WindowAccessController(service: StubWindowAccessService(status: .enabled))
        let applications = StubApplicationMenuService()
        let windows = StubApplicationWindowService()
        let controller = ApplicationMenuController(access: access, applications: applications, windows: windows)
        let item = dockItem(running: true, available: true)
        let token = ApplicationWindowToken(sessionID: UUID(), id: UUID())

        let firstError = await perform(controller, action: .selectWindow(token), item: item)
        #expect(firstError == nil)
        #expect(await windows.selectedTokens() == [token])

        await windows.setSelectionError(.windowUnavailable)
        let secondError = await perform(controller, action: .selectWindow(token), item: item)
        #expect(secondError != nil)
        controller.stop()
    }

    @Test("Application commands route independently and surface partial-process rejection")
    func applicationActionRouting() async {
        let access = WindowAccessController(service: StubWindowAccessService(status: .notEnabled))
        let applications = StubApplicationMenuService()
        applications.processSnapshots = [
            ApplicationProcessSnapshot(processIdentifier: 71, isHidden: false, isActive: true),
            ApplicationProcessSnapshot(processIdentifier: 72, isHidden: false, isActive: false),
        ]
        let controller = ApplicationMenuController(
            access: access,
            applications: applications,
            windows: StubApplicationWindowService()
        )
        let item = dockItem(running: true, available: true)

        #expect(await perform(controller, action: .showInFinder, item: item) == nil)
        #expect(await perform(controller, action: .setHidden(true), item: item) == nil)
        #expect(await perform(controller, action: .setHidden(false), item: item) == nil)
        #expect(await perform(controller, action: .bringAllToFront, item: item) == nil)
        #expect(await perform(controller, action: .quit, item: item) == nil)
        #expect(applications.actions == [.showInFinder, .setHidden(true), .setHidden(false), .bringAllToFront, .quit])

        applications.error = .operationRejected
        #expect(await perform(controller, action: .quit, item: item) != nil)
        applications.error = .applicationUnavailable
        #expect(await perform(controller, action: .bringAllToFront, item: item) != nil)
        controller.stop()
    }

    private func discover(_ controller: ApplicationMenuController,
                          item: DockItem,
                          snapshot: ApplicationMenuSnapshot) async -> ApplicationWindowMenuState {
        await withCheckedContinuation { continuation in
            let sessionID = controller.beginDiscovery(for: item, snapshot: snapshot) { state in
                continuation.resume(returning: state)
            }
            #expect(sessionID != nil)
        }
    }

    private func perform(_ controller: ApplicationMenuController,
                         action: ApplicationMenuAction,
                         item: DockItem) async -> LocalizedStringResource? {
        await withCheckedContinuation { continuation in
            controller.perform(action, for: item) { continuation.resume(returning: $0) }
        }
    }

    private func dockItem(running: Bool, available: Bool) -> DockItem {
        DockItem(
            reference: DisplayFixtures.app("menu.fixture"),
            icon: NSImage(size: NSSize(width: 48, height: 48)),
            isFavorite: true,
            isRunning: running,
            isAvailable: available
        )
    }

    private func window(_ title: String?, sessionID: UUID, minimized: Bool = false,
                        main: Bool = false) -> ApplicationWindowSummary {
        ApplicationWindowSummary(
            token: ApplicationWindowToken(sessionID: sessionID, id: UUID()),
            processIdentifier: 100,
            title: title,
            frame: CGRect(x: 10, y: 20, width: 800, height: 600),
            isMinimized: minimized,
            isMain: main
        )
    }
}

@MainActor
private final class StubWindowAccessService: WindowAccessServicing {
    var status: WindowAccessStatus
    var requests = 0
    var settingsOpens = 0
    init(status: WindowAccessStatus) { self.status = status }
    func requestAccess() { requests += 1 }
    func openSystemSettings() { settingsOpens += 1 }
}

@MainActor
private final class StubApplicationMenuService: ApplicationMenuServicing {
    var processSnapshots: [ApplicationProcessSnapshot] = []
    var actions: [ApplicationMenuAction] = []
    var error: ApplicationMenuServiceError?

    func processes(for reference: ApplicationReference) -> [ApplicationProcessSnapshot] { processSnapshots }
    func showInFinder(_ reference: ApplicationReference) throws { try record(.showInFinder) }
    func setHidden(_ hidden: Bool, for reference: ApplicationReference) throws { try record(.setHidden(hidden)) }
    func bringAllToFront(_ reference: ApplicationReference) throws { try record(.bringAllToFront) }
    func quit(_ reference: ApplicationReference) throws { try record(.quit) }

    private func record(_ action: ApplicationMenuAction) throws {
        actions.append(action)
        if let error { throw error }
    }
}

private actor StubApplicationWindowService: ApplicationWindowServicing {
    private var discoveryResult: Result<[ApplicationWindowSummary], ApplicationWindowServiceError> = .success([])
    private var selectionError: ApplicationWindowServiceError?
    private var selected: [ApplicationWindowToken] = []
    private var discarded: [UUID] = []
    private let delay: Duration?

    init(delay: Duration? = nil) { self.delay = delay }

    func setDiscoveryResult(_ result: Result<[ApplicationWindowSummary], ApplicationWindowServiceError>) {
        discoveryResult = result
    }

    func setSelectionError(_ error: ApplicationWindowServiceError?) { selectionError = error }
    func selectedTokens() -> [ApplicationWindowToken] { selected }
    func discardedSessions() -> [UUID] { discarded }

    func discover(processes: [ApplicationProcessSnapshot], sessionID: UUID) async throws -> [ApplicationWindowSummary] {
        if let delay { try await Task.sleep(for: delay) }
        return try discoveryResult.get().map {
            ApplicationWindowSummary(
                token: ApplicationWindowToken(sessionID: sessionID, id: $0.token.id),
                processIdentifier: $0.processIdentifier,
                title: $0.title,
                frame: $0.frame,
                isMinimized: $0.isMinimized,
                isMain: $0.isMain
            )
        }
    }

    func selectWindow(_ token: ApplicationWindowToken) throws {
        selected.append(token)
        if let selectionError { throw selectionError }
    }

    func discard(sessionID: UUID) { discarded.append(sessionID) }
    func stop() {}
}
