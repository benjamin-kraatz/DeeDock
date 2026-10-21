// DOKK Sample Plugin: a developer example, never shipped with DOKK. See docs/PLUGINS.md.
//
// A plugin author can copy this file next to DOKKPluginContract/. It is the plugin side of the
// contract: it accepts DOKK's connections, pushes tile state, and hands over DOKK's events.

import Foundation
import Observation
import os

/// The plugin's end of every connection DOKK opens to it.
///
/// DOKK keeps one background connection while the plugin's tile is pinned. All of them share this
/// one object, so a change made in the panel reaches the tile whichever connection carries it.
/// Set ``tileState`` and every open connection receives it.
///
/// When DOKK lets go of the last connection (the tile was unpinned or DOKK quit), the process exits
/// a few seconds later, unless a new connection arrives first. ExtensionKit does not end idle
/// plugin processes on its own while DOKK runs.
@MainActor @Observable
final class DOKKPluginHostLink {
    /// What DOKK's tile shows. Every change is sent to every connection.
    var tileState: DOKKPluginTileState {
        didSet { if tileState != oldValue { push() } }
    }
    /// Open connections from DOKK.
    private(set) var connectionCount = 0
    /// The contract version DOKK reported, once it connected.
    private(set) var hostContractVersion: Int?
    /// Receives DOKK's events on the main actor: panel open and close, menu choices.
    @ObservationIgnored var onEvent: ((DOKKPluginHostEvent) -> Void)?
    /// Exits once DOKK has no connection left. Turn off for a plugin with its own reasons to run.
    @ObservationIgnored var exitsWhenUnused = true

    @ObservationIgnored private var connections: [ObjectIdentifier: NSXPCConnection] = [:]
    @ObservationIgnored private var exitTask: Task<Void, Never>?
    nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DOKKPlugin",
                                                   category: "host-link")

    init(tileState: DOKKPluginTileState) {
        self.tileState = tileState
    }

    /// Accepts a connection from DOKK. Pass it from both the extension's `ConnectionHandler` and the
    /// panel scene's `onConnection`. ExtensionKit calls those off the main thread.
    nonisolated func accept(_ connection: NSXPCConnection) -> Bool {
        let key = ObjectIdentifier(connection)
        connection.configureDOKKPlugin(as: .plugin, exporting: DOKKPluginEndpoint(link: self))
        let forget: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.forget(key) }
        }
        connection.invalidationHandler = forget
        connection.interruptionHandler = forget
        connection.resume()
        nonisolated(unsafe) let accepted = connection
        Task { @MainActor in self.remember(accepted, key: key) }
        return true
    }

    /// Asks DOKK to do something, such as close the panel.
    func request(_ request: DOKKPluginRequest) {
        let data = request.encoded()
        for connection in connections.values {
            (connection.remoteObjectProxyWithErrorHandler { _ in } as? DOKKPluginHostService)?.perform(data)
        }
    }

    // MARK: - From DOKK

    fileprivate func connected(hostInfo: DOKKPluginHostInfo) {
        hostContractVersion = hostInfo.contractVersion
    }

    fileprivate func received(_ event: DOKKPluginHostEvent) {
        if event == .willDisconnect { scheduleExitIfUnused() }
        onEvent?(event)
    }

    // MARK: - Connections

    private func remember(_ connection: NSXPCConnection, key: ObjectIdentifier) {
        connections[key] = connection
        connectionCount = connections.count
        exitTask?.cancel()
        exitTask = nil
        Self.logger.info("DOKK connected, \(self.connectionCount) connection(s)")
    }

    private func forget(_ key: ObjectIdentifier) {
        guard connections.removeValue(forKey: key) != nil else { return }
        connectionCount = connections.count
        Self.logger.info("DOKK disconnected, \(self.connectionCount) connection(s)")
        scheduleExitIfUnused()
    }

    /// Waits a moment, so a restart that reconnects at once keeps the process.
    private func scheduleExitIfUnused() {
        guard exitsWhenUnused, exitTask == nil else { return }
        exitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.connections.isEmpty else {
                self?.exitTask = nil
                return
            }
            Self.logger.info("No DOKK connection left; exiting")
            exit(0)
        }
    }

    private func push() {
        let data = tileState.encoded()
        for connection in connections.values {
            (connection.remoteObjectProxyWithErrorHandler { _ in } as? DOKKPluginHostService)?.tileStateDidChange(data)
        }
    }

    fileprivate var encodedTileState: Data { tileState.encoded() }
}

/// The object DOKK calls. Runs on the connection's queue and hops to the main actor.
private nonisolated final class DOKKPluginEndpoint: NSObject, DOKKPluginService {
    private weak var link: DOKKPluginHostLink?

    init(link: DOKKPluginHostLink) { self.link = link }

    func connect(_ hostInfo: Data, reply: @escaping (Data) -> Void) {
        nonisolated(unsafe) let reply = reply
        let info = DOKKPluginHostInfo.decode(hostInfo) ?? DOKKPluginHostInfo()
        Task { @MainActor [weak link] in
            link?.connected(hostInfo: info)
            reply(link?.encodedTileState ?? Data())
        }
    }

    func fetchTileState(reply: @escaping (Data) -> Void) {
        nonisolated(unsafe) let reply = reply
        Task { @MainActor [weak link] in reply(link?.encodedTileState ?? Data()) }
    }

    func handle(_ event: Data) {
        guard let event = DOKKPluginHostEvent.decode(event) else { return }
        Task { @MainActor [weak link] in link?.received(event) }
    }
}
