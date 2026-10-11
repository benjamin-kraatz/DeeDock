import Foundation
import os

/// Owns DOKK's `NSXPCConnection` to `LookoutIndexService` and exports `LookoutIndexStatusReceiver` on it.
///
/// The service exits about a minute after it runs out of work, which interrupts the connection, and a relaunched
/// service knows nothing. So this remembers the last configuration and the pause state, and the next message that
/// needs the service replays them first (`pause()` if paused, then `start(configuration:)`, which also syncs). An
/// interruption by itself relaunches nothing: the service stays gone until something asks for work, which is what
/// returns its memory.
///
/// A message can be lost in the instant the service decides to exit (`IdleExit` holds its lock until the process
/// ends). Every request for work is therefore followed by `currentStatus`, a barrier: messages on one connection
/// arrive in order, so its reply proves the request arrived. An interruption before that reply replays the request,
/// at most `maxReplays` times in a row, so a service that dies at launch can't loop.
///
/// Main actor: all state lives there; NSXPC handlers and replies hop to the main queue first. Every proxy call has an
/// error handler; failures surface through the interruption and invalidation handlers.
@MainActor final class LookoutIndexConnection: LookoutIndexControlling {
    /// Replays of an unacknowledged request before giving up until the next one.
    static let maxReplays = 3

    var onStatus: ((LookoutIndexStatus) -> Void)?
    var onConnectionEvent: ((LookoutIndexConnectionEvent) -> Void)?
    private(set) var isServiceRunning = false

    private let serviceName: String
    private var connection: NSXPCConnection?
    private var configuration: LookoutIndexConfiguration?
    private var paused = false
    /// A request for work was sent and its barrier hasn't replied yet.
    private var awaitingAcknowledgement = false
    private var replaysWithoutAcknowledgement = 0

    /// - Parameter serviceName: `LookoutServiceNames.index(appBundleIdentifier:)`.
    init(serviceName: String) {
        self.serviceName = serviceName
    }

    isolated deinit {
        connection?.invalidate()
    }

    // MARK: LookoutIndexControlling

    func start(_ configuration: LookoutIndexConfiguration) {
        self.configuration = configuration
        replaysWithoutAcknowledgement = 0
        launch()
    }

    func syncNow() {
        guard configuration != nil else { return }
        guard isServiceRunning else { return launch() }
        requestWork { $0.syncNow() }
    }

    func setBackfillAllowed(_ allowed: Bool) {
        configuration?.backfillAllowed = allowed
        guard isServiceRunning else { return }
        proxy()?.setBackfillAllowed(allowed)
    }

    func pause() {
        paused = true
        guard isServiceRunning else { return }
        proxy()?.pause()
    }

    func resume() {
        paused = false
        guard configuration != nil else { return }
        guard isServiceRunning else { return launch() }
        requestWork { $0.resume() }
    }

    func invalidate() {
        let old = connection
        connection = nil
        configuration = nil
        isServiceRunning = false
        awaitingAcknowledgement = false
        old?.invalidate()
    }

    // MARK: Messages

    /// Sends the remembered state to a (possibly new) service process: the pause first, then the configuration.
    private func launch() {
        guard let configuration, let data = try? configuration.encoded(), let service = proxy() else { return }
        if paused { service.pause() }
        isServiceRunning = true
        awaitingAcknowledgement = true
        service.start(configuration: data) { @Sendable [weak self] error in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.acknowledged(rejection: error) } }
        }
    }

    /// Sends a request for work, then the barrier that proves it arrived.
    private func requestWork(_ send: (any LookoutIndexServing) -> Void) {
        guard let service = proxy() else { return }
        awaitingAcknowledgement = true
        send(service)
        let receiver = statusReceiver
        service.currentStatus { @Sendable [weak self] data in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.acknowledged(rejection: nil) } }
            receiver?.receive(data)
        }
    }

    private func acknowledged(rejection: String?) {
        awaitingAcknowledgement = false
        replaysWithoutAcknowledgement = 0
        if let rejection {
            LookoutLog.logger.error("The index service refused its configuration: \(rejection, privacy: .public)")
        }
    }

    // MARK: Connection

    /// Kept so `currentStatus` replies can be delivered like pushed statuses.
    private var statusReceiver: LookoutIndexStatusReceiver?

    private func proxy() -> (any LookoutIndexServing)? {
        let proxy = liveConnection().remoteObjectProxyWithErrorHandler { @Sendable error in
            // The interruption or invalidation handler deals with what this means for the connection.
            LookoutLog.logger.error("Index service call failed: \(error.localizedDescription, privacy: .public)")
        }
        return proxy as? any LookoutIndexServing
    }

    private func liveConnection() -> NSXPCConnection {
        if let connection { return connection }
        let made = NSXPCConnection(serviceName: serviceName)
        made.remoteObjectInterface = NSXPCInterface(with: LookoutIndexServing.self)
        made.exportedInterface = NSXPCInterface(with: LookoutIndexClient.self)
        let receiver = LookoutIndexStatusReceiver { [weak self] status in self?.onStatus?(status) }
        made.exportedObject = receiver
        statusReceiver = receiver
        let id = ObjectIdentifier(made)
        made.interruptionHandler = { @Sendable [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.interrupted(id) } }
        }
        made.invalidationHandler = { @Sendable [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.invalidated(id) } }
        }
        made.resume()
        connection = made
        return made
    }

    /// The service process ended. Nothing relaunches it unless a request for work may have been lost.
    private func interrupted(_ id: ObjectIdentifier) {
        guard let connection, ObjectIdentifier(connection) == id else { return }
        isServiceRunning = false
        onConnectionEvent?(.interrupted)
        guard awaitingAcknowledgement, configuration != nil else { return }
        guard replaysWithoutAcknowledgement < Self.maxReplays else {
            awaitingAcknowledgement = false
            LookoutLog.logger.error("The index service keeps exiting before it answers; waiting for the next request")
            return
        }
        replaysWithoutAcknowledgement += 1
        launch()
    }

    /// The service can't be reached. The next message makes a new connection; nothing is replayed now.
    private func invalidated(_ id: ObjectIdentifier) {
        guard let current = connection, ObjectIdentifier(current) == id else { return }
        connection = nil
        statusReceiver = nil
        isServiceRunning = false
        awaitingAcknowledgement = false
        onConnectionEvent?(.unavailable)
    }
}
