import Foundation
import os

/// The object DOKK exports on the index service's connection (`LookoutIndexClient`). NSXPC calls it on the
/// connection's serial queue; it decodes there and hands each status to the main queue in arrival order (the main
/// queue is FIFO, so statuses never overtake each other).
nonisolated final class LookoutIndexStatusReceiver: NSObject, LookoutIndexClient, @unchecked Sendable {
    private let deliver: @MainActor (LookoutIndexStatus) -> Void

    /// - Parameter deliver: Called on the main actor with each decoded status.
    init(deliver: @escaping @MainActor (LookoutIndexStatus) -> Void) {
        self.deliver = deliver
    }

    func indexStatusDidChange(_ status: Data) {
        receive(status)
    }

    /// Decodes `data` and delivers it on the main actor; data that doesn't decode is dropped.
    func receive(_ data: Data) {
        guard let status = try? LookoutIndexStatus.decode(data) else {
            LookoutLog.logger.error("Dropped an index status that doesn't decode")
            return
        }
        let deliver = deliver
        DispatchQueue.main.async { MainActor.assumeIsolated { deliver(status) } }
    }
}
