import AppKit
import os

/// User-visible interactions DDock measures. Raw values are the keys in benchmark JSON.
nonisolated enum PerformanceMetric: String, CaseIterable, Sendable {
    /// Process start to the first dock panel on screen.
    case launch
    /// Native input entering the activation zone to the auto-hidden dock ordered on screen.
    /// Includes the configured reveal delay.
    case dockReveal
    /// Native input over the dock to the first magnified layout committed.
    case hoverResponse
    /// Pointer change to the magnified layout committed, driven in-process without native input.
    case magnifyUpdate
    case stackOpen
    case peekOpen
    /// Launcher request to the expanded panel's first frame committed.
    case launcherOpen
    /// The click on the launcher tile to the expanded panel's first frame committed.
    case launcherOpenFromClick
    /// Query change to ranked results committed. Includes the search debounce.
    case launcherQuery
    /// Ranking work alone, without the debounce or rendering.
    case launcherRank
    case windowSearchOpen
}

/// Signposts for the interactions users feel, visible under Instruments' Points of Interest.
///
/// Recording costs a few flag checks when neither Instruments nor a benchmark is listening.
/// Interval ends mark the point where the result was committed to the render server, not when a method
/// returned: SwiftUI and AppKit build the frame at the end of the current run-loop turn.
@MainActor
enum PerformanceSignposts {
    struct Interval {
        fileprivate let metric: PerformanceMetric
        fileprivate let state: OSSignpostIntervalState
        fileprivate let start: TimeInterval
    }

    private static let signposter = OSSignposter(subsystem: "de.benjaminkraatz.DeeDock", category: .pointsOfInterest)
    /// Receives milliseconds per completed interval. Only the benchmark recorder sets it.
    static var sink: ((PerformanceMetric, Double) -> Void)?
    /// Whether native input timestamps are tracked for end-to-end metrics. Only the benchmark recorder sets it.
    static var tracksInput = false
    /// Newest pointer movement. Keys and clicks are excluded: a hover or reveal they cause, such as the
    /// dock reappearing under a still pointer after Escape closes the Launcher, is not a pointer response.
    private static var lastInput: TimeInterval?
    private static var launchRecorded = false

    private static var listening: Bool { sink != nil || signposter.isEnabled }

    static func begin(_ metric: PerformanceMetric) -> Interval? {
        guard listening else { return nil }
        let id = signposter.makeSignpostID()
        return Interval(metric: metric, state: beginState(metric, id: id), start: ProcessInfo.processInfo.systemUptime)
    }

    /// Ends immediately. Use for work that produces no frame, such as ranking.
    static func end(_ interval: Interval?) {
        guard let interval else { return }
        endState(interval.metric, interval.state)
        sink?(interval.metric, (ProcessInfo.processInfo.systemUptime - interval.start) * 1_000)
    }

    /// Ends after Core Animation commits the current run-loop turn's changes.
    static func endAfterCommit(_ interval: Interval?) {
        guard let interval else { return }
        afterCommit { end(interval) }
    }

    /// Closes a superseded interval in Instruments without reporting a sample.
    static func cancel(_ interval: Interval?) {
        guard let interval else { return }
        endState(interval.metric, interval.state)
    }

    /// Remembers the newest pointer movement so an end-to-end metric can start at its hardware timestamp.
    static func noteInput(_ event: NSEvent) {
        guard tracksInput else { return }
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: lastInput = event.timestamp
        default: lastInput = nil
        }
    }

    /// Reports the time from the newest pointer movement to the next commit. Input older than `window`
    /// seconds did not cause this change, so nothing is reported.
    static func commitSinceInput(_ metric: PerformanceMetric, within window: TimeInterval = 1) {
        guard tracksInput, let input = lastInput, ProcessInfo.processInfo.systemUptime - input <= window else { return }
        lastInput = nil
        afterCommit {
            signposter.emitEvent("Committed", "\(metric.rawValue, privacy: .public)")
            sink?(metric, (ProcessInfo.processInfo.systemUptime - input) * 1_000)
        }
    }

    /// Reports the time from the event that triggered this change, such as a click, to the next commit.
    static func commitSince(_ event: NSEvent?, _ metric: PerformanceMetric) {
        guard let event, listening, ProcessInfo.processInfo.systemUptime - event.timestamp <= 1 else { return }
        let start = event.timestamp
        afterCommit {
            signposter.emitEvent("Committed", "\(metric.rawValue, privacy: .public)")
            sink?(metric, (ProcessInfo.processInfo.systemUptime - start) * 1_000)
        }
    }

    /// Records launch time once, when the first dock panel is ordered on screen.
    static func dockPanelOrderedFront() {
        guard !launchRecorded else { return }
        launchRecorded = true
        guard listening, let started = processStart else { return }
        afterCommit {
            let milliseconds = (Date().timeIntervalSince1970 - started) * 1_000
            signposter.emitEvent("Launch", "\(milliseconds, privacy: .public) ms")
            sink?(.launch, milliseconds)
        }
    }

    /// Runs `action` once, right after Core Animation's next implicit commit.
    ///
    /// Core Animation commits from a run-loop observer on `beforeWaiting` and `exit`, ordered at 2,000,000.
    /// This observer watches the same activities at the last possible order. Both matter: a turn that handled
    /// a source skips `beforeWaiting`, and AppKit's event loop leaves the run loop after each dequeued event.
    /// The observer is non-repeating, so the run loop invalidates it after it fires.
    private static func afterCommit(_ action: @escaping @MainActor () -> Void) {
        let activities = CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue
        let observer = CFRunLoopObserverCreateWithHandler(nil, activities, false, CFIndex.max) { _, _ in
            MainActor.assumeIsolated { action() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    /// Wall-clock process start from the kernel, so launch time includes dyld and static initialization.
    private static var processStart: TimeInterval? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1e6
    }

    // `OSSignposter` requires static-string names, so each metric maps to a literal.
    private static func beginState(_ metric: PerformanceMetric, id: OSSignpostID) -> OSSignpostIntervalState {
        switch metric {
        case .launch: signposter.beginInterval("launch", id: id)
        case .dockReveal: signposter.beginInterval("dockReveal", id: id)
        case .hoverResponse: signposter.beginInterval("hoverResponse", id: id)
        case .magnifyUpdate: signposter.beginInterval("magnifyUpdate", id: id)
        case .stackOpen: signposter.beginInterval("stackOpen", id: id)
        case .peekOpen: signposter.beginInterval("peekOpen", id: id)
        case .launcherOpen: signposter.beginInterval("launcherOpen", id: id)
        case .launcherOpenFromClick: signposter.beginInterval("launcherOpenFromClick", id: id)
        case .launcherQuery: signposter.beginInterval("launcherQuery", id: id)
        case .launcherRank: signposter.beginInterval("launcherRank", id: id)
        case .windowSearchOpen: signposter.beginInterval("windowSearchOpen", id: id)
        }
    }

    private static func endState(_ metric: PerformanceMetric, _ state: OSSignpostIntervalState) {
        switch metric {
        case .launch: signposter.endInterval("launch", state)
        case .dockReveal: signposter.endInterval("dockReveal", state)
        case .hoverResponse: signposter.endInterval("hoverResponse", state)
        case .magnifyUpdate: signposter.endInterval("magnifyUpdate", state)
        case .stackOpen: signposter.endInterval("stackOpen", state)
        case .peekOpen: signposter.endInterval("peekOpen", state)
        case .launcherOpen: signposter.endInterval("launcherOpen", state)
        case .launcherOpenFromClick: signposter.endInterval("launcherOpenFromClick", state)
        case .launcherQuery: signposter.endInterval("launcherQuery", state)
        case .launcherRank: signposter.endInterval("launcherRank", state)
        case .windowSearchOpen: signposter.endInterval("windowSearchOpen", state)
        }
    }
}
