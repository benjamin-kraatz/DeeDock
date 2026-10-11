import Foundation

/// The object every XPC connection to `LookoutIndexService` exports. It turns messages into requests for the one
/// `IndexWork` the process has, and keeps track of the connected apps that hear about status changes.
///
/// NSXPC calls it on its own queues, so it holds no state besides what `IndexWork` and `StatusBroadcaster` guard.
final class IndexServiceController: NSObject, LookoutIndexServing, @unchecked Sendable {
    /// Shared by all connections: one index, one model.
    static let shared = IndexServiceController()

    private let status: StatusBroadcaster
    private let work: IndexWork

    override init() {
        status = StatusBroadcaster()
        work = IndexWork(status: status)
        super.init()
    }

    /// The process launched.
    func launched() {
        work.launched()
    }

    /// A connection was accepted: its app hears every status from now on, and work may go on.
    func connected(_ connection: NSXPCConnection) {
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            // The app went away mid-send; its invalidation handler removes it.
        }
        if let client = proxy as? any LookoutIndexClient { status.add(client, for: ObjectIdentifier(connection)) }
        work.setAppConnected(true)
    }

    /// A connection went away. With no app left, work stops after the current batch, and the process exits once
    /// idle.
    func disconnected(_ connection: ObjectIdentifier) {
        if status.remove(connection) == 0 { work.setAppConnected(false) }
    }

    // MARK: LookoutIndexServing

    func start(configuration: Data, reply: @escaping @Sendable (String?) -> Void) {
        do {
            work.configure(try LookoutIndexConfiguration.decode(configuration))
            reply(nil)
        } catch {
            reply("can't read the configuration: \(error)")
        }
    }

    func syncNow() { work.syncNow() }
    func setBackfillAllowed(_ allowed: Bool) { work.setBackfillAllowed(allowed) }
    func pause() { work.pause() }
    func resume() { work.resume() }

    func currentStatus(reply: @escaping @Sendable (Data) -> Void) {
        reply((try? status.current.encoded()) ?? Data())
    }
}
