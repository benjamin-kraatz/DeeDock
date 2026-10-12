import Foundation

/// Runs blocking or CPU-bound work, such as large reads, hashing, decoding and resizing, on a dispatch queue instead
/// of Swift's cooperative thread pool, and hands the result back to the awaiting task.
///
/// The cooperative pool has one thread per core. Work that holds a pool thread for long stalls every task and actor
/// waiting for one. That's what timed out the Lookout tests in parallel on CI's few cores, and it would stall the
/// app's other async work while a picture is read from a slow volume or a downloaded model is hashed.
/// `LookoutPictureReading` and `LookoutModelInstaller` use this.
nonisolated enum LookoutBlockingWork {
    /// Cancellation for work on a dispatch queue, where `Task.checkCancellation` can't see the caller's task: the
    /// caller's cancellation handler sets it, and the work checks it between steps.
    final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false   // guarded by `lock`

        func cancel() { lock.withLock { cancelled = true } }

        /// - Throws: `CancellationError` once `cancel()` was called.
        func check() throws {
            if lock.withLock({ cancelled }) { throw CancellationError() }
        }
    }

    /// Runs `work` on `queue` and returns its result. Cancelling the calling task cancels `work` through the
    /// `Cancellation` it's given. A caller that's already cancelled starts nothing, and work that hasn't begun when
    /// its caller is cancelled doesn't run.
    ///
    /// - Throws: What `work` throws, or `CancellationError`.
    static func run<T: Sendable>(on queue: DispatchQueue,
                                 _ work: @escaping @Sendable (Cancellation) throws -> T) async throws -> T {
        try Task.checkCancellation()
        let cancellation = Cancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    continuation.resume(with: Result { try cancellation.check(); return try work(cancellation) })
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}
