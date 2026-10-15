import Foundation

/// Holds the index service's latest status and sends it to every connected app, at most ten times a second.
///
/// Updates come from the work queue as often as files finish (several a second for images); sending each one would
/// flood the app's main thread with decoding. Updates within 100 ms of the last send are coalesced: one send carries
/// the latest status when the interval is up, so the last update always arrives. Sends run on a queue of their own;
/// NSXPC proxies may be messaged from any thread.
final class StatusBroadcaster: @unchecked Sendable {
    /// The shortest time between two sends.
    static let interval: DispatchTimeInterval = .milliseconds(100)

    private let queue = DispatchQueue(label: "Lookout.Index.status", qos: .utility)
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var latest = LookoutIndexStatus()
    private var clients: [ObjectIdentifier: any LookoutIndexClient] = [:]
    private var lastSent = DispatchTime(uptimeNanoseconds: 0)
    private var sendScheduled = false

    /// The latest status (what `currentStatus` replies).
    var current: LookoutIndexStatus { lock.withLock { latest } }

    /// Changes the status and schedules a send.
    func update(_ change: (inout LookoutIndexStatus) -> Void) {
        let changed = lock.withLock { () -> Bool in
            let before = latest
            change(&latest)
            return latest != before
        }
        if changed { scheduleSend() }
    }

    /// Starts sending to a connection's exported client, and sends it the current status.
    func add(_ client: any LookoutIndexClient, for connection: ObjectIdentifier) {
        lock.withLock { clients[connection] = client }
        scheduleSend()
    }

    /// Stops sending to a connection that went away. Returns how many connections are left.
    @discardableResult
    func remove(_ connection: ObjectIdentifier) -> Int {
        lock.withLock {
            clients[connection] = nil
            return clients.count
        }
    }

    private func scheduleSend() {
        let deadline = lock.withLock { () -> DispatchTime? in
            guard !sendScheduled else { return nil }
            sendScheduled = true
            return max(.now(), lastSent + Self.interval)
        }
        guard let deadline else { return }
        queue.asyncAfter(deadline: deadline) { [self] in send() }
    }

    private func send() {
        let (status, targets) = lock.withLock { () -> (LookoutIndexStatus, [any LookoutIndexClient]) in
            sendScheduled = false
            lastSent = .now()
            return (latest, Array(clients.values))
        }
        guard !targets.isEmpty, let data = try? status.encoded() else { return }
        for client in targets { client.indexStatusDidChange(data) }
    }
}
