import Foundation

/// Ends a Lookout XPC service once it has been idle for a while, so the memory its model holds (0.25–1 GB) goes back
/// to the system. launchd relaunches the service for the next message, and the app's connection survives that: it
/// sees an interruption, and its next call starts a fresh process.
///
/// DigUp's helper did the same by exiting after its last file. `arm` and `disarm` may be called from any thread; the
/// owner decides what idle means. The timer fires on `queue`, the service's serial work queue, so `beforeExit` never
/// runs beside work queued there.
nonisolated final class IdleExit: @unchecked Sendable {
    private let delay: DispatchTimeInterval
    private let queue: DispatchQueue
    private let beforeExit: () -> Void
    private let lock = NSLock()
    /// Bumped by every `arm` and `disarm`, so a timer armed earlier can tell it's stale when it fires.
    private var generation = 0

    /// - Parameters:
    ///   - seconds: How long the service must stay idle.
    ///   - queue: Where the exit runs (the service's serial work queue).
    ///   - beforeExit: Last cleanup on `queue` (free the model, remove scratch files). It must not call `arm` or
    ///     `disarm`.
    init(after seconds: Int, on queue: DispatchQueue, beforeExit: @escaping () -> Void = {}) {
        delay = .seconds(seconds)
        self.queue = queue
        self.beforeExit = beforeExit
    }

    /// The service went idle: exit after the delay unless `disarm` or another `arm` comes first.
    func arm() {
        let armed = lock.withLock { () -> Int in
            generation += 1
            return generation
        }
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            // The lock is held until the process ends: a call that disarmed first keeps the service, and one that
            // comes later waits here and never runs. Its sender sees the connection interrupted, and resends.
            lock.lock()
            guard generation == armed else {
                lock.unlock()
                return
            }
            beforeExit()
            exit(0)
        }
    }

    /// Work arrived: stay.
    func disarm() {
        lock.withLock { generation += 1 }
    }
}
