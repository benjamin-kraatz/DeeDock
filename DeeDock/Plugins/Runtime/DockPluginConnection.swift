import ExtensionFoundation
import Foundation
import os

/// One background session with a plugin's process, independent of any visible panel.
///
/// `AppExtensionProcess` launches (or reuses) the plugin process and hands back an XPC connection.
/// The tile's state arrives over it whether or not the panel is open; the plugin spike measured the
/// panel's scene and this connection reaching the same process.
///
/// Every callback is delivered once on the main actor. After ``stop()`` or the first ``Event/ended(unexpected:)``
/// the session is finished and reports nothing more; a restart makes a new session.
@MainActor
final class DockPluginConnection: DockPluginSession {
    typealias Event = DockPluginSessionEvent

    private let identity: AppExtensionIdentity
    private let onEvent: (Event) -> Void
    private var process: AppExtensionProcess?
    private var connection: NSXPCConnection?
    private var startTask: Task<Void, Never>?
    /// Ends a session whose plugin never answers, so its tile does not wait forever.
    private var replyTimeout: Task<Void, Never>?
    private var finished = false
    /// Coalesces the plugin's tile states: only the newest undelivered one reaches the main actor.
    private let stateMailbox = DockPluginStateMailbox()
    /// How long a plugin has to send its first tile state, launch included. The spike measured
    /// replies within 0.3 seconds of a cold start.
    private static let replyDeadline: Duration = .seconds(15)
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DOKK", category: "Plugins")

    init(identity: AppExtensionIdentity, onEvent: @escaping (Event) -> Void) {
        self.identity = identity
        self.onEvent = onEvent
    }

    /// Launches the plugin process and asks for its first tile state.
    func start() {
        guard startTask == nil, !finished else { return }
        // ExtensionKit calls this when the process goes away under a live session.
        let configuration = AppExtensionProcess.Configuration(appExtensionIdentity: identity) { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.end(unexpected: true, reason: "process interrupted") }
        }
        replyTimeout = Task { [weak self] in
            try? await Task.sleep(for: Self.replyDeadline)
            guard !Task.isCancelled else { return }
            self?.end(unexpected: true, reason: "no reply")
        }
        startTask = Task { [weak self] in
            do {
                let process = try await AppExtensionProcess(configuration: configuration)
                guard let self, !self.finished else { process.invalidate(); return }
                self.attach(process)
            } catch {
                self?.end(unexpected: true, reason: "launch failed: \(error)")
            }
        }
    }

    private func attach(_ process: AppExtensionProcess) {
        let connection: NSXPCConnection
        do {
            connection = try process.makeXPCConnection()
        } catch {
            process.invalidate()
            end(unexpected: true, reason: "connection failed: \(error)")
            return
        }
        let mailbox = stateMailbox
        // Every tile state goes through the mailbox, so a plugin that floods DOKK costs at most
        // one pending main-actor task, and a late `connect` reply can't replace a newer push.
        let enqueueState: @Sendable (DOKKPluginTileState) -> Void = { [weak self] state in
            guard let self, mailbox.put(state) else { return }
            Task { @MainActor in self.deliverLatestState() }
        }
        let endpoint = DockPluginHostEndpoint(stateChanged: enqueueState, requested: { [weak self] request in
            guard let self else { return }
            Task { @MainActor in self.deliver(.request(request)) }
        })
        connection.configureDOKKPlugin(as: .host, exporting: endpoint)
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.end(unexpected: true, reason: "connection interrupted") }
        }
        // Also fires after DOKK's own invalidate, which `finished` already filters out.
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.end(unexpected: true, reason: "connection invalidated") }
        }
        connection.resume()
        self.process = process
        self.connection = connection
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in self?.end(unexpected: true, reason: "connect failed: \(error.localizedDescription)") }
        } as? DOKKPluginService
        proxy?.connect(DOKKPluginHostInfo().encoded()) { data in
            guard let state = DockPluginHostEndpoint.decodeState(data) else { return }
            enqueueState(state)
        }
    }

    /// Asks the plugin for its state again, for example when Settings opens.
    func refresh() {
        guard !finished, let connection else { return }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in } as? DOKKPluginService
        let mailbox = stateMailbox
        proxy?.fetchTileState { [weak self] data in
            guard let self, let state = DockPluginHostEndpoint.decodeState(data), mailbox.put(state) else { return }
            Task { @MainActor in self.deliverLatestState() }
        }
    }

    /// Tells the plugin about something that happened in DOKK. Dropped once the session ended.
    func send(_ event: DOKKPluginHostEvent) {
        guard !finished, let connection else { return }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in } as? DOKKPluginService
        proxy?.handle(event.encoded())
    }

    /// Ends the session on DOKK's side.
    ///
    /// Sends ``DOKKPluginHostEvent/willDisconnect`` first, then invalidates the connection and the
    /// process handle once that message has left. The plugin spike saw plugin processes outlive every
    /// host reference by minutes, so the event is what lets a plugin with nothing else open exit.
    /// Reports no event. Safe to call more than once.
    func stop() {
        guard !finished else { return }
        send(.willDisconnect)
        finished = true
        startTask?.cancel()
        startTask = nil
        replyTimeout?.cancel()
        replyTimeout = nil
        let connection = connection
        let process = process
        self.connection = nil
        self.process = nil
        guard let connection else { process?.invalidate(); return }
        // The barrier runs after every message sent so far, so willDisconnect is not dropped.
        nonisolated(unsafe) let barrierConnection = connection
        nonisolated(unsafe) let barrierProcess = process
        connection.scheduleSendBarrierBlock {
            barrierConnection.invalidate()
            barrierProcess?.invalidate()
        }
    }

    /// Only a tile state proves the plugin answers; a request alone leaves the tile with nothing
    /// to show, so the deadline keeps running.
    static func endsReplyDeadline(_ event: Event) -> Bool {
        if case .state = event { return true }
        return false
    }

    /// Delivers the newest state waiting in the mailbox, if any.
    private func deliverLatestState() {
        guard let state = stateMailbox.take() else { return }
        deliver(.state(state))
    }

    private func deliver(_ event: Event) {
        guard !finished else { return }
        if Self.endsReplyDeadline(event) {
            replyTimeout?.cancel()
            replyTimeout = nil
        }
        onEvent(event)
    }

    private func end(unexpected: Bool, reason: String) {
        guard !finished else { return }
        finished = true
        Self.logger.info("Plugin session ended: \(reason, privacy: .public)")
        startTask = nil
        replyTimeout?.cancel()
        replyTimeout = nil
        connection?.invalidate()
        process?.invalidate()
        connection = nil
        process = nil
        onEvent(.ended(unexpected: unexpected))
    }
}
