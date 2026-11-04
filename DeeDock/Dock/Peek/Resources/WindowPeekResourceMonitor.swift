import AppKit

/// Samples one app's CPU, memory, and network while a Window Peek is open, and stops when it closes.
///
/// CPU and memory come from `AppHealthProcessSampler`, so a number here means the same thing as
/// App Health: the main process plus helpers whose parent chain or bundle path reaches the app.
/// Network uses those same process ids. System helpers launchd starts from `/System`, such as
/// Safari's WebContent processes, are absent for the same reason. The libproc pass runs on the
/// sampler's actor, and network callbacks arrive on their own queue. Nothing is written down.
@MainActor
final class WindowPeekResourceMonitor {
    /// How long to wait between passes. The first pass only establishes counters, so CPU appears
    /// after one interval. Memory is reported immediately.
    static let interval: Duration = .seconds(1)

    /// The latest reading, or nil when the app has no process this pass can read.
    var onReading: ((WindowPeekResourceReading?) -> Void)?

    private var task: Task<Void, Never>?
    private let network = WindowPeekNetworkReader()
    /// Bumped by `start` and `stop`, so a pass already in libproc cannot publish after Peek moved on.
    private var generation = UUID()

    /// Begins sampling `reference`. A Peek that is already sampling is replaced; its last pass is dropped.
    func start(reference: ApplicationReference) {
        let generation = UUID()
        self.generation = generation
        task?.cancel()
        network.start()
        let sampler = AppHealthProcessSampler()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == generation else { return }
                let apps = WindowPeekResourceTarget.apps(matching: reference)
                let reading: WindowPeekResourceReading?
                if let key = apps.first?.bundleID {
                    let result = await sampler.sample(apps)
                    guard !Task.isCancelled, self.generation == generation else { return }
                    let rate = self.networkRate(pids: result.pids[key] ?? [], interval: result.interval)
                    reading = result.usage[key].flatMap {
                        WindowPeekResourceReading(usage: $0, interval: result.interval, network: rate)
                    }
                    self.network.refresh()
                } else {
                    reading = nil
                }
                guard self.generation == generation else { return }
                self.onReading?(reading)
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    /// Cancels the pass and ignores any sample already in flight.
    func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
        network.stop()
        onReading = nil
    }

    /// Bytes arrived since the previous pass, divided by that pass's interval.
    ///
    /// The first counts callback for a flow is a baseline, not traffic from this second. A
    /// description that arrives earlier has no counters, so it cannot be that baseline. Otherwise
    /// a connection that has been open for an hour would show as one huge rate.
    private func networkRate(pids: Set<pid_t>, interval: Double?) -> WindowPeekNetworkRate? {
        guard let delta = network.bytesSinceLastRead(matching: pids), let interval, interval > 0 else { return nil }
        return WindowPeekNetworkRate(receivedPerSecond: Double(delta.received) / interval,
                                     sentPerSecond: Double(delta.sent) / interval)
    }
}

/// The running instances of one dock app, in the shape the sampler already attributes.
enum WindowPeekResourceTarget {
    /// Every live instance of `reference`. Instances share one key, the bundle identifier or, when
    /// the app has none, the bundle path, so their use is added together.
    static func apps(matching reference: ApplicationReference) -> [AppHealthWatchedApp] {
        let key = reference.bundleIdentifier ?? reference.url.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.compactMap { application in
            guard !application.isTerminated, matches(application, reference) else { return nil }
            return AppHealthWatchedApp(bundleID: key, kind: AppHealthAppKind(application.activationPolicy),
                                       pid: application.processIdentifier,
                                       bundlePath: application.bundleURL?.standardizedFileURL.path)
        }
    }

    /// Bundle identity wins, because a pinned app may have moved. A reference with no bundle
    /// identifier matches the standardized bundle path.
    private static func matches(_ application: NSRunningApplication, _ reference: ApplicationReference) -> Bool {
        if let bundleIdentifier = reference.bundleIdentifier {
            return application.bundleIdentifier == bundleIdentifier
        }
        return application.bundleURL?.standardizedFileURL == reference.url.standardizedFileURL
    }
}
