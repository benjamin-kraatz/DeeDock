import ApplicationServices
import Foundation
import Synchronization

/// A dedicated thread with its own run loop for Flix Files' Accessibility observer.
///
/// Registering an `AXObserver` notification and reading an app's focused window are IPC to that
/// app; a busy or hung app answers late, and on the main thread that stalls the dock. Everything
/// the front-window observer asks of other apps runs here instead, one block at a time in order,
/// and the observer's run-loop source lives on this run loop, so its callbacks arrive here too.
/// Results go back to the main actor, which discards any that are stale.
///
/// One thread for the process, started on first use and kept for the app's lifetime: it sleeps in
/// its run loop when idle and costs nothing. A far-future timer keeps the run loop alive while it
/// has no sources.
nonisolated final class FlixAXThread: Sendable {
    static let shared = FlixAXThread()

    private let runLoop = Mutex<CFRunLoop?>(nil)

    private init() {}

    /// Runs `block` on the thread, after the blocks enqueued before it.
    func perform(_ block: @escaping @Sendable () -> Void) {
        let loop = loop
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(loop)
    }

    /// The thread's run loop, for an observer's source. Add and remove sources only from a block
    /// passed to ``perform(_:)``, so they change on the thread that runs them.
    var loop: CFRunLoop {
        runLoop.withLock { loop in
            if let loop { return loop }
            let started = Self.startThread()
            loop = started
            return started
        }
    }

    private static func startThread() -> CFRunLoop {
        let created = Mutex<CFRunLoop?>(nil)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            created.withLock { $0 = CFRunLoopGetCurrent() }
            let keepAlive = CFRunLoopTimerCreateWithHandler(nil, .greatestFiniteMagnitude, 0, 0, 0) { _ in }
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), keepAlive, .defaultMode)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "DOKK Flix Accessibility"
        thread.qualityOfService = .userInitiated
        thread.start()
        // Only the first use waits, for the moment the thread takes to start.
        ready.wait()
        return created.withLock { $0! }
    }
}
