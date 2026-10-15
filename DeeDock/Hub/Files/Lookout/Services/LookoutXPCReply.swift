import Foundation
import os

/// Turns one XPC call with a reply into an `async` result that settles exactly once: with the reply, the proxy's error
/// handler, a timeout, or the calling task's cancellation, whichever comes first. Later ones are ignored, so a reply
/// that arrives after a timeout can't resume the continuation twice.
///
/// Thread-safe: replies and error handlers arrive on NSXPC's queues, the timeout on a global queue, cancellation on
/// any thread.
nonisolated final class LookoutXPCReply<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    /// A result that came before the continuation was installed (cancelled before the call started).
    private var early: Result<Value, Error>?
    private var settled = false
    private var timeout: DispatchWorkItem?

    /// Settles the call. Only the first call has any effect.
    func finish(_ result: Result<Value, Error>) {
        let resume = lock.withLock { () -> CheckedContinuation<Value, Error>? in
            guard !settled else { return nil }
            settled = true
            timeout?.cancel()
            timeout = nil
            guard let continuation else {
                early = result
                return nil
            }
            self.continuation = nil
            return continuation
        }
        resume?.resume(with: result)
    }

    /// Runs `send`, which starts the XPC call and arranges for `finish` to be called, and waits for the result.
    ///
    /// - Parameters:
    ///   - timeout: How long to wait before failing with `LookoutEncoderError.timedOut`.
    ///   - send: Called once, synchronously, on the caller's actor.
    /// - Throws: Whatever `finish` was given, `LookoutEncoderError.timedOut`, or `CancellationError`.
    static func call(timeout: Duration, _ send: (LookoutXPCReply<Value>) -> Void) async throws -> Value {
        let reply = LookoutXPCReply<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                reply.install(continuation, timeout: timeout)
                send(reply)
            }
        } onCancel: {
            reply.finish(.failure(CancellationError()))
        }
    }

    private func install(_ continuation: CheckedContinuation<Value, Error>, timeout: Duration) {
        let early = lock.withLock { () -> Result<Value, Error>? in
            if let early { return early }
            self.continuation = continuation
            let work = DispatchWorkItem { [weak self] in self?.finish(.failure(LookoutEncoderError.timedOut)) }
            self.timeout = work
            let (seconds, attoseconds) = timeout.components
            let nanoseconds = Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .nanoseconds(nanoseconds), execute: work)
            return nil
        }
        if let early { continuation.resume(with: early) }
    }
}

/// Why the query encoder gave no vector. Never shown as is: search falls back to keyword results.
nonisolated enum LookoutEncoderError: Error, Equatable, CustomStringConvertible {
    /// No reply within the call's time limit.
    case timedOut
    /// The service couldn't be reached, or went away before replying.
    case unavailable
    /// The service replied with an error (a missing model file, a load failure).
    case service(String)
    /// The reply wasn't one vector of the right width.
    case badReply

    var description: String {
        switch self {
        case .timedOut: "the query encoder didn't reply in time"
        case .unavailable: "the query encoder can't be reached"
        case .service(let message): "the query encoder failed: \(message)"
        case .badReply: "the query encoder's reply isn't a vector"
        }
    }
}

/// Lookout's log category.
nonisolated enum LookoutLog {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DeeDock", category: "Lookout")
}
