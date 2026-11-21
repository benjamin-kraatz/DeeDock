import AppKit
import ApplicationServices

/// Follows the frontmost app for Flix Pick and hands its picker events to the main actor.
///
/// NSWorkspace's activation notification reports app switches; after a short settle (so flicking
/// through apps with Command-Tab costs nothing) the one ``FlixPickSession`` moves its `AXObserver`
/// to the new app on ``FlixAXThread``. DOKK itself and the apps in ``excluded`` are never observed,
/// so DOKK's own pickers never get a Flix Pick. Every switch bumps the session's generation, so
/// queued work for an earlier app is skipped.
///
/// Operations on the picker (``run(_:)``) are short blocks on the same thread, awaited from the
/// main actor; the elements stay on the thread.
///
/// ``stop()`` removes the workspace observer and, on the thread, every notification and the
/// run-loop source. Needs Accessibility permission; without it the session never attaches and
/// nothing is reported. It never asks for the permission. Main actor.
@MainActor
final class FlixPickObserver {
    static let settle: Duration = .milliseconds(120)

    /// Picker events, in order.
    var event: ((FlixPickEvent) -> Void)?
    /// Bundle identifiers never observed.
    var excluded: Set<String> = [] {
        didSet {
            guard excluded != oldValue, isRunning else { return }
            activated(NSWorkspace.shared.frontmostApplication)
        }
    }
    private(set) var isRunning = false

    private let session = FlixPickSession()
    private var workspaceObserver: NSObjectProtocol?
    private var pending: Task<Void, Never>?

    init() {
        session.deliver = { [weak self] event in self?.event?(event) }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.activated(app) }
        }
        activated(NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        pending?.cancel()
        pending = nil
        detach()
    }

    private func detach() {
        let generation = session.advance()
        let session = session
        FlixAXThread.shared.perform { session.detach(generation: generation) }
    }

    private func activated(_ app: NSRunningApplication?) {
        pending?.cancel()
        // Any attach queued for the previous app is now stale, and its picker is hidden at once.
        detach()
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !(app.bundleIdentifier.map(excluded.contains) ?? false) else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settle)
            guard let self, !Task.isCancelled, isRunning, !app.isTerminated,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
            let generation = session.advance()
            let session = session
            let pid = app.processIdentifier
            FlixAXThread.shared.perform { session.attach(to: pid, generation: generation) }
        }
    }

    /// Runs `operation` on the Accessibility thread, after the blocks queued before it.
    func run<T: Sendable>(_ operation: @escaping @Sendable (FlixPickSession) -> T) async -> T {
        let session = session
        return await withCheckedContinuation { continuation in
            FlixAXThread.shared.perform { continuation.resume(returning: operation(session)) }
        }
    }
}
