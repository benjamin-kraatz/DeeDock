import AppKit
import Observation

/// One explicitly started, memory-only watch. Closing its panel cancels every owned task.
/// What the panel shows about a watch, in the order a watch moves through it.
enum WindowWatchPhase {
    case preparing, ready, watching, detected, ended
}

@MainActor @Observable
final class WindowWatchSession {
    let title: String
    let appName: String
    let icon: NSImage?
    var region = WindowWatchRegion()
    var usesPhrase = false
    var phrase = ""
    var playSound = false
    var image: CGImage?
    var message: LocalizedStringResource = .watchPreparing
    var ready = false
    var active = false
    var finished = false
    var lastSample: Date?
    var sourceMessage: LocalizedStringResource?
    /// The condition was met. Kept apart from `finished`, which a manual stop also sets.
    var detected = false
    /// The current message reports a problem rather than progress, so the panel can mark it.
    var problem = false
    var startDate: Date?
    var checkCount = 0
    var activity: [WindowWatchActivityEntry] = []
    let explanation = WindowWatchExplanation()

    var phase: WindowWatchPhase {
        if detected { return .detected }
        if active { return .watching }
        if ready { return .ready }
        if finished { return .ended }
        return .preparing
    }
    @ObservationIgnored private let capture = WindowWatchCapture()
    @ObservationIgnored private let process: NSRunningApplication?
    @ObservationIgnored private let launchDate: Date?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var sourceTask: Task<Void, Never>?
    @ObservationIgnored private var staleTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var suspensionReasons: Set<String> = []
    @ObservationIgnored private var detector = WindowWatchDetector()
    @ObservationIgnored private var size: CGSize?
    @ObservationIgnored private var pixelSize: CGSize?
    @ObservationIgnored var dismiss: (() -> Void)?

    init(summary: ApplicationWindowSummary, after previousWork: Task<Void, Never>? = nil) {
        title = summary.title ?? String(localized: .applicationMenuUntitledWindow)
        let application = NSRunningApplication(processIdentifier: summary.processIdentifier)
        appName = application?.localizedName ?? ""
        icon = application?.icon
        process = application
        launchDate = process?.launchDate
        observeLifecycle()
        task = Task { [weak self] in
            await previousWork?.value
            guard let self, !Task.isCancelled else { return }
            defer { staleTask?.cancel() }
            do {
                _ = try validateProcess()
                watchForStaleCapture()
                try await capture.prepare(summary)
                _ = try validateProcess()
                while !Task.isCancelled {
                    do {
                        let process = try validateProcess()
                        watchForStaleCapture()
                        let frame = try await capture.sample(region: region, recognizeText: false,
                                                             isAppHidden: process.isHidden)
                        try Task.checkCancellation()
                        _ = try validateProcess()
                        image = frame.image
                        ready = true
                        message = .watchSetupHelp
                        return
                    } catch {
                        staleTask?.cancel()
                        guard !Task.isCancelled else { return }
                        fail(error)
                        guard case .offscreen = error as? WindowWatchFailure else { return }
                        // Keep the fixed identity while setup waits for the selected window to become visible.
                        try await Task.sleep(for: .seconds(3))
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                fail(error)
            }
        }
    }

    #if DEBUG
    /// Deterministic preview state with no capture service calls, observers, or permission requests.
    init(previewTitle: String, message: LocalizedStringResource, setup: Bool) {
        title = previewTitle
        appName = previewTitle
        icon = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        process = nil
        launchDate = nil
        self.message = message
        ready = setup
        finished = !setup
    }
    #endif

    func start() {
        guard ready, !active, !finished else { return }
        phrase = String(phrase.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
        guard !usesPhrase || !phrase.isEmpty else { return }
        task?.cancel()
        active = true
        ready = false
        problem = false
        detected = false
        checkCount = 0
        activity = []
        explanation.cancel()
        startDate = Date()
        detector = WindowWatchDetector()
        size = nil
        generation = UUID()
        run()
    }

    /// Returns a drain barrier so a replacement watch cannot overlap an in-flight OS request.
    @discardableResult
    func stop() -> Task<Void, Never> {
        explanation.cancel()
        let pendingCapture = task
        let pendingSource = sourceTask
        generation = UUID()
        task?.cancel()
        sourceTask?.cancel()
        staleTask?.cancel()
        active = false
        ready = false
        finished = true
        detected = false
        problem = false
        startDate = nil
        message = .watchStopped
        removeObservers()
        return Task {
            await pendingCapture?.value
            await pendingSource?.value
        }
    }

    func close() {
        stop()
        image = nil
        dismiss?()
        dismiss = nil
    }

    /// Opening the source is always an explicit action; monitoring, Stop and Dismiss never activate it.
    func showWindow() {
        guard sourceTask == nil else { return }
        sourceMessage = nil
        guard let process = try? validateProcess() else { sourceMessage = .watchClosed; return }
        sourceTask = Task { [weak self] in
            guard let self else { return }
            let windows = AccessibilityApplicationWindowService()
            let id = UUID()
            do {
                let summaries = try await windows.discover(processes: [ApplicationProcessSnapshot(
                    processIdentifier: process.processIdentifier, isHidden: process.isHidden, isActive: process.isActive)], sessionID: id)
                let token = try await capture.sourceToken(in: summaries)
                try Task.checkCancellation()
                _ = try validateProcess()
                try await windows.selectWindow(token)
            } catch {
                if !Task.isCancelled { sourceMessage = .watchSourceUnavailable }
            }
            await windows.discard(sessionID: id)
            sourceTask = nil
        }
    }

    func showSource() {
        guard let process = try? validateProcess() else {
            message = .watchClosed
            return
        }
        process.activate()
    }

    private func run() {
        guard active else { return }
        guard suspensionReasons.isEmpty else { message = .watchSuspended; return }
        let expected = generation
        let watchedRegion = region
        let watchedPhrase = usesPhrase ? phrase : ""
        let previousTask = task
        task = Task { [weak self] in
            // Await the cancelled capture before starting another: actor reentrancy alone does not serialize awaits.
            await previousTask?.value
            guard let self, !Task.isCancelled, generation == expected else { return }
            while active && !Task.isCancelled && generation == expected {
                do {
                    let process = try validateProcess()
                    message = .watchSampling
                    watchForStaleCapture()
                    let frame = try await capture.sample(region: watchedRegion, recognizeText: !watchedPhrase.isEmpty, isAppHidden: process.isHidden)
                    staleTask?.cancel()
                    guard !Task.isCancelled, generation == expected else { return }
                    _ = try validateProcess()
                    // Geometry changes invalidate evidence. A resized layout requires a new baseline.
                    if size != frame.size || pixelSize != frame.pixelSize {
                        resetEvidence()
                        size = frame.size
                        pixelSize = frame.pixelSize
                    }
                    image = frame.image
                    lastSample = Date()
                    checkCount += 1
                    problem = false
                    explanation.retainBaseline(frame.regionImage)
                    let matched = detector.consume(pixels: frame.pixels, lines: frame.lines, phrase: watchedPhrase)
                    recordObservation(matched ? .confirmed : detector.observation)
                    if matched {
                        active = false
                        finished = true
                        detected = true
                        message = watchedPhrase.isEmpty ? .watchChangeDetected : .watchPhraseDetected
                        if playSound { NSSound.beep() }
                        explanation.explain(final: frame.regionImage)
                        removeObservers()
                        task = nil
                        return
                    }
                    message = watchedPhrase.isEmpty ? .watchWatching : .watchWaitingPhrase
                } catch {
                    staleTask?.cancel()
                    guard !Task.isCancelled, generation == expected else { return }
                    resetEvidence()
                    fail(error)
                    if !active { removeObservers(); return }
                }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }

    /// Keep recent transitions only. Repeated motion updates one row instead of flooding history.
    private func recordObservation(_ observation: WindowWatchObservation) {
        let now = Date()
        if activity.last?.observation == observation {
            activity[activity.count - 1].date = now
        } else {
            activity.append(WindowWatchActivityEntry(observation: observation, date: now))
            if activity.count > 12 { activity.removeFirst(activity.count - 12) }
        }
    }

    private func resetEvidence() {
        detector = WindowWatchDetector()
        explanation.resetBaseline()
        if checkCount > 0 { recordObservation(.reset) }
    }

    private func validateProcess() throws -> NSRunningApplication {
        guard let process, let launchDate, !process.isTerminated, process.launchDate == launchDate else {
            throw WindowWatchFailure.closed
        }
        return process
    }

    private func watchForStaleCapture() {
        staleTask?.cancel()
        let expected = generation
        staleTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, !Task.isCancelled, generation == expected, !finished, active || !ready else { return }
            message = .watchStale
        }
    }

    private func fail(_ error: Error) {
        problem = true
        switch error as? WindowWatchFailure {
        case .permission:
            message = .watchPermission
            active = false
            finished = true
            image = nil
        case .closed:
            message = .watchClosed
            active = false
            finished = true
            image = nil
        case .offscreen: message = .watchOffscreen
        default: message = .watchUnavailable
        }
    }

    private func observeLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "sleep"),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "display"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session")
        ]
        for (pause, resume, reason) in pairs {
            for (name, suspended) in [(pause, true), (resume, false)] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.suspend(reason: reason, suspended: suspended) }
                })
            }
        }
    }

    private func suspend(reason: String, suspended: Bool) {
        if suspended { suspensionReasons.insert(reason) } else { suspensionReasons.remove(reason) }
        guard active else {
            if !finished {
                generation = UUID()
                task?.cancel()
                staleTask?.cancel()
                ready = false
                image = nil
                message = .watchSetupInterrupted
            }
            return
        }
        generation = UUID()
        task?.cancel()
        staleTask?.cancel()
        resetEvidence()
        image = nil
        message = .watchSuspended
        if suspensionReasons.isEmpty { run() }
    }

    private func removeObservers() {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
    }
}
