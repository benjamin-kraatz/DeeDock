import AppKit

/// How one Drop to Place ended. Raw values are the `outcome` analytics tokens.
nonisolated enum DropPlacementOutcome: String, Sendable {
    /// A launched app's first window was moved to the target.
    case placed
    /// A running app's front window was moved to the target.
    case moved
    /// Accessibility is off, so the app was opened or activated where macOS put it.
    case openedUnplaced = "opened_unplaced"
    /// No window appeared within ``DropPlacementService/windowTimeout``.
    case timedOut = "timed_out"
    /// The launch failed, the app refused the move, or the work was cancelled.
    case failed
}

/// Opens or moves an app's window to a target frame after a drop.
///
/// Task ownership: at most one placement runs per app (keyed by `ApplicationReference.id`).
/// Starting another for the same app, ``cancel(applicationID:)``, or ``stop()`` cancels the
/// earlier task, and a cancelled task reports `.failed` only if nobody replaced it. Each task
/// owns one `DropPlacementWindowObserver` and stops it before finishing.
@MainActor
final class DropPlacementService {
    /// How long a launch may take to show its first window before the landing pad gives up.
    static let windowTimeout: Duration = .seconds(10)
    /// The longest gap between window checks while waiting. AX notifications usually wake the
    /// wait sooner; this backstop covers apps that post none, and only runs during the wait.
    static let recheckInterval: Duration = .milliseconds(500)

    /// One placement. `open` asks macOS to open or activate the app through the dock's normal
    /// path, so the tile bounces and errors appear as usual, and reports whether it succeeded.
    struct Request {
        let reference: ApplicationReference
        /// Global AppKit coordinates.
        let frame: CGRect
        let open: (@escaping (Bool) -> Void) -> Void
    }

    private let accessibility: DropPlacementAccessibility
    private var tasks: [String: (id: UUID, task: Task<Void, Never>)] = [:]

    init(accessibility: DropPlacementAccessibility) {
        self.accessibility = accessibility
    }

    /// Places the app's window at `request.frame`, launching the app when needed.
    /// - Parameter completion: Called once on the main actor with the outcome and, when a
    ///   window moved, the frame it accepted in AppKit coordinates. Not called for a placement
    ///   replaced by a newer one for the same app.
    func place(_ request: Request, completion: @escaping (DropPlacementOutcome, CGRect?) -> Void) {
        let key = request.reference.id
        tasks[key]?.task.cancel()
        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            let (outcome, frame) = await run(request)
            guard tasks[key]?.id == id else { return }
            tasks[key] = nil
            completion(outcome, frame)
        }
        tasks[key] = (id, task)
    }

    /// Cancels the app's pending placement, for example because the same app is dragged again.
    func cancel(applicationID: String) {
        tasks.removeValue(forKey: applicationID)?.task.cancel()
    }

    func stop() {
        tasks.values.forEach { $0.task.cancel() }
        tasks.removeAll()
    }

    private func run(_ request: Request) async -> (DropPlacementOutcome, CGRect?) {
        let deadline = ContinuousClock.now + Self.windowTimeout
        let target = Self.quartz(request.frame)
        // A running app with a window moves at once, then comes forward.
        if let app = Self.runningApplication(for: request.reference),
           await accessibility.frontWindowFrame(processIdentifier: app.processIdentifier) != nil {
            guard !Task.isCancelled else { return (.failed, nil) }
            let accepted = try? await accessibility.setFrontWindowFrame(processIdentifier: app.processIdentifier, to: target)
            guard !Task.isCancelled else { return (.failed, nil) }
            request.open { _ in }
            guard let accepted = accepted ?? nil else { return (.failed, nil) }
            return (.moved, Self.appKit(accepted))
        }
        // Not running, or running without a window: open it (the reopen event makes a window)
        // and wait for the first window to show up.
        var launchFailed = false
        request.open { succeeded in if !succeeded { launchFailed = true } }
        let observer = DropPlacementWindowObserver()
        defer { observer.stop() }
        while ContinuousClock.now < deadline {
            guard !Task.isCancelled, !launchFailed else { return (.failed, nil) }
            if let app = Self.runningApplication(for: request.reference) {
                observer.observe(app.processIdentifier)
                if await accessibility.frontWindowFrame(processIdentifier: app.processIdentifier) != nil {
                    guard !Task.isCancelled else { return (.failed, nil) }
                    // A read that came back after the deadline must not move a window late.
                    guard ContinuousClock.now < deadline else { break }
                    let accepted = try? await accessibility.setFrontWindowFrame(processIdentifier: app.processIdentifier,
                                                                               to: target, deadline: deadline)
                    guard let accepted = accepted ?? nil else {
                        return (ContinuousClock.now >= deadline ? .timedOut : .failed, nil)
                    }
                    return (.placed, Self.appKit(accepted))
                }
            }
            let remaining = deadline - ContinuousClock.now
            await observer.next(timeout: min(Self.recheckInterval, max(.zero, remaining)))
        }
        return (launchFailed ? .failed : .timedOut, nil)
    }

    /// The regular process for `reference`, matched by bundle identifier, else by bundle URL.
    static func runningApplication(for reference: ApplicationReference) -> NSRunningApplication? {
        let candidates = reference.bundleIdentifier.map { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            ?? NSWorkspace.shared.runningApplications.filter {
                $0.bundleURL?.standardizedFileURL == reference.url.standardizedFileURL
            }
        return candidates.first { !$0.isTerminated && $0.activationPolicy == .regular }
    }

    /// AppKit global frame (y up, origin at the primary display's bottom-left) to the Quartz
    /// top-left frame Accessibility expects. The AppKit top-left corner is `(minX, maxY)`.
    static func quartz(_ frame: CGRect) -> CGRect {
        CGRect(origin: AppMeltGeometry.quartz(fromAppKit: CGPoint(x: frame.minX, y: frame.maxY)), size: frame.size)
    }

    /// The inverse of ``quartz(_:)``, for frames read back from Accessibility.
    static func appKit(_ frame: CGRect) -> CGRect {
        AppMeltGeometry.appKit(frame, primaryTop: AppMeltGeometry.mainDisplayTop())
    }
}
