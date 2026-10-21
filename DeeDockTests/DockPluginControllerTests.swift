import Foundation
import Testing
@testable import DeeDock

/// DEE-140: the plugin controller's session handling, driven through fake sessions so no
/// ExtensionKit plugin or process is involved.
@MainActor
struct DockPluginControllerTests {
    /// Records what the controller asks of a session and lets the test answer for the plugin.
    final class FakeSession: DockPluginSession {
        let report: (DockPluginSessionEvent) -> Void
        private(set) var started = false
        private(set) var stopped = false
        var sent: [DOKKPluginHostEvent] = []

        init(report: @escaping (DockPluginSessionEvent) -> Void) { self.report = report }

        func start() { started = true }
        func refresh() {}
        func send(_ event: DOKKPluginHostEvent) { sent.append(event) }
        func stop() { stopped = true }
    }

    private let id = "com.example.Test.Plugin"
    private let suite = "DockPluginControllerTests.\(UUID().uuidString)"

    /// A controller with one enabled plugin, and every session it makes, in order.
    private func makeController() throws -> (DockPluginController, () -> [FakeSession]) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        var sessions: [FakeSession] = []
        let controller = DockPluginController(pins: DockPluginPinStore(defaults: defaults)) { _, report in
            let session = FakeSession(report: report)
            sessions.append(session)
            return session
        }
        controller.apply([DockPluginRecord(id: id, name: "Test", identity: nil)], waiting: 0, disabled: 0)
        return (controller, { sessions })
    }

    private func cleanUp() { UserDefaults().removePersistentDomain(forName: suite) }

    @Test("A newly approved plugin is pinned and started")
    func newPluginStarts() throws {
        defer { cleanUp() }
        let (controller, sessions) = try makeController()
        #expect(controller.dockItems.map(\.pluginID) == [id])
        #expect(controller.plugin(id)?.status == .starting)
        #expect(sessions().count == 1 && sessions()[0].started)
        sessions()[0].report(.state(DOKKPluginTileState(badge: .count(2))))
        #expect(controller.plugin(id)?.status == .running)
        #expect(controller.plugin(id)?.badge?.label == "2")
    }

    @Test("A panel opened before the plugin answered is announced once it does")
    func panelOpenedBeforeFirstReply() throws {
        defer { cleanUp() }
        let (controller, sessions) = try makeController()
        controller.notePanel(id, open: true)
        // A real session drops events sent before it connects.
        sessions()[0].sent.removeAll()
        sessions()[0].report(.state(DOKKPluginTileState()))
        #expect(sessions()[0].sent == [.panelOpened])
        sessions()[0].report(.state(DOKKPluginTileState(badge: .dot)))
        #expect(sessions()[0].sent == [.panelOpened])
    }

    @Test("Restarting a crashed plugin with its panel open tells the new session")
    func restartWithPanelOpen() throws {
        defer { cleanUp() }
        let (controller, sessions) = try makeController()
        sessions()[0].report(.state(DOKKPluginTileState()))
        controller.notePanel(id, open: true)
        sessions()[0].report(.ended(unexpected: true))
        #expect(controller.plugin(id)?.status == .stopped)
        #expect(controller.dockItems.first?.isStopped == true)

        controller.restart(id, surface: .panel)
        #expect(sessions().count == 2 && sessions()[1].started)
        #expect(controller.plugin(id)?.status == .starting)
        sessions()[1].report(.state(DOKKPluginTileState()))
        #expect(sessions()[1].sent == [.panelOpened])
        #expect(controller.plugin(id)?.status == .running)
        #expect(controller.dockItems.first?.isStopped == false)
    }

    @Test("A scene that fails while the plugin starts stops it, with Restart offered")
    func sceneFailureWhileStarting() throws {
        defer { cleanUp() }
        let (controller, sessions) = try makeController()
        controller.sceneFailed(id)
        #expect(controller.plugin(id)?.status == .stopped)
        #expect(sessions()[0].stopped)
        // The ended session's late reports are ignored by the real session; the controller has let go.
        controller.restart(id, surface: .panel)
        #expect(sessions().count == 2)
    }

    @Test("Unpinning closes the panel and ends the session")
    func unpinEndsSession() throws {
        defer { cleanUp() }
        let (controller, sessions) = try makeController()
        var closed: [String] = []
        controller.closePanel = { closed.append($0) }
        controller.setPinned(id, false, surface: .settings)
        #expect(closed == [id])
        #expect(sessions()[0].stopped)
        #expect(controller.plugin(id)?.status == .idle)
        #expect(controller.dockItems.isEmpty)
        controller.setPinned(id, true, surface: .settings)
        #expect(sessions().count == 2 && controller.dockItems.map(\.pluginID) == [id])
    }

    @Test("A plugin that disappears loses its session and its tile")
    func removedPluginDisconnects() throws {
        defer { cleanUp() }
        let (controller, sessions) = try makeController()
        controller.apply([], waiting: 1, disabled: 0)
        #expect(sessions()[0].stopped)
        #expect(controller.dockItems.isEmpty && controller.plugins.isEmpty)
        #expect(controller.waitingCount == 1)
    }
}
