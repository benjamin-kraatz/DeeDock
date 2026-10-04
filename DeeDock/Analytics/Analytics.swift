import AppKit


/// The single entry point for anonymous usage analytics.
///
/// Call sites only ever do two things: `Analytics.track(_:)` for a feature event and
/// `Analytics.count(_:)` for an interaction that is too frequent to send one by one. Both append
/// to memory and return, so they are safe on pointer and rendering paths. Building the payload
/// happens on a later main-actor turn and the backend runs on its own serial queue.
///
/// Nothing reaches the backend unless all of these hold:
/// - the build carries an API key (and, in a debug build, the debug-menu switch is on),
/// - "Share anonymous usage data" is on,
/// - a new user has been shown the notice in the tour or in Settings.
///
/// Events tracked before the notice is shown wait in memory and are released when it appears,
/// or are lost when the app quits first. `docs/ANALYTICS.md` describes what is collected.
@MainActor
final class Analytics {
    /// The process-wide instance. Previews and the test host get one that stores nothing and
    /// sends nothing.
    static let shared: Analytics = HostEnvironment.isPreview || HostEnvironment.isTestHost ? Analytics() : .live()

    let consent: AnalyticsConsentStore
    /// What was recently handed to the backend, for the Settings card.
    let recent: AnalyticsRecentLog
    /// False when this build has no API key or no analytics SDK; the Settings card says so.
    let isConfigured: Bool

    /// See ``performing(_:_:)``.
    var ambientTrigger: AnalyticsTrigger?
    /// Supplies live app state for the context. Set by the composition root before ``start()``.
    var contextInputs: (() -> AnalyticsContextInputs)?

    private let backend: any AnalyticsBackend
    private let counters: AnalyticsCounterStore
    private let defaults: UserDefaults?
    /// Every backend call after `start` runs here, in order, off the main thread.
    private let queue = DispatchQueue(label: "de.benjaminkraatz.DeeDock.analytics", qos: .utility)

    private var pending: [AnalyticsEvent] = []
    private var drainScheduled = false
    private var backendStarted = false
    private var registered = AnalyticsProperties()
    private var settingChanges: [String: PendingSettingChange] = [:]
    private var settingFlush: Task<Void, Never>?
    private var contextRefresh: Task<Void, Never>?
    private var maintenance: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var appearanceObservation: NSKeyValueObservation?

    private struct PendingSettingChange {
        var change: AnalyticsSettingChange
        var area: AnalyticsSettingArea
        var display: AnalyticsDisplayRole?
    }

    /// Events held while a new user has not seen the notice. Older ones are dropped beyond this.
    private static let pendingLimit = 500
    private static let summaryInterval: TimeInterval = 24 * 60 * 60
    private static let debugSendingKey = "analytics.debug-send.v1"

    #if DEBUG
    /// Debug builds send nothing unless this debug-menu switch is on. Events then go to the
    /// same project tagged `channel=debug`.
    var debugSendingEnabled: Bool {
        didSet {
            guard debugSendingEnabled != oldValue else { return }
            defaults?.set(debugSendingEnabled, forKey: Self.debugSendingKey)
            if debugSendingEnabled { activateIfAllowed() } else { deactivate() }
        }
    }
    #endif

    /// - Parameters:
    ///   - backend: where permitted events go. The default discards them.
    ///   - defaults: nil keeps consent and counters in memory, for previews and tests.
    ///   - recent: lets a preview show a prepared "recently sent" list.
    init(backend: any AnalyticsBackend = NoOpAnalyticsBackend(), defaults: UserDefaults? = nil,
         recent: AnalyticsRecentLog? = nil) {
        let recent = recent ?? AnalyticsRecentLog()
        self.defaults = defaults
        self.recent = recent
        self.backend = RecordingAnalyticsBackend(base: backend, log: recent)
        isConfigured = backend.isConfigured
        consent = AnalyticsConsentStore(defaults: defaults, isExistingInstall: {
            defaults.map(AnalyticsConsentStore.hasEarlierLaunch(in:)) ?? false
        })
        counters = AnalyticsCounterStore(defaults: defaults)
        #if DEBUG
        debugSendingEnabled = defaults?.bool(forKey: Self.debugSendingKey) ?? false
        #endif
    }

    private static func live() -> Analytics {
        Analytics(backend: AnalyticsBackendFactory.live(), defaults: .standard)
    }

    // MARK: - Call-site API

    /// Queues a feature event. Returns at once; a disabled or unconfigured build drops it.
    static func track(_ event: AnalyticsEvent) { shared.track(event) }

    /// Adds to a high-frequency counter that is reported in the next `usage_summary`.
    static func count(_ counter: AnalyticsCounter) { shared.count(counter) }

    static func log(_ message: String, attributes: AnalyticsProperties = [:]) {
        shared.log(message, attributes: attributes)
    }

    static func captureAI(_ record: AIObservabilityRecord) { shared.captureAI(record) }

    func track(_ event: AnalyticsEvent) {
        guard acceptsEvents else { return }
        pending.append(event)
        if pending.count > Self.pendingLimit { pending.removeFirst(pending.count - Self.pendingLimit) }
        scheduleDrain()
    }

    func count(_ counter: AnalyticsCounter) {
        guard acceptsEvents else { return }
        counters.increment(counter)
    }

    private func log(_ message: String, attributes: AnalyticsProperties) {
        guard acceptsEvents, backendStarted else { return }
        let record = AnalyticsLogRecord(message: message, attributes: attributes)
        queue.async { [backend] in backend.captureLog(record) }
    }

    private func captureAI(_ record: AIObservabilityRecord) {
        guard acceptsEvents, backendStarted else { return }
        queue.async { [backend] in backend.captureAI(record) }
    }

    /// Reports one smart-grouping request from the organizer actor: whether groups were
    /// generated or served from cache, how long it took, and a failure code.
    nonisolated static func trackSmartGrouping(_ request: SemanticStackRequest, result: AnalyticsSmartGroupingResult,
                                               since start: Date, failure: AnalyticsSmartGroupingFailure? = nil) {
        let duration = Date().timeIntervalSince(start)
        let source: AnalyticsSmartGroupingSource = request.source == .shelf ? .shelf : .folder
        let count = request.candidates.count
        Task { @MainActor in
            track(.smartGrouping(source, result: result, duration: duration, candidateCount: count, failure: failure))
        }
    }

    /// Reports every setting that differs between two versions of a settings model.
    ///
    /// Edits to the same setting within a couple of seconds, such as a slider drag, become one
    /// `setting_changed` event from the first old value to the last new value.
    func settingsChanged(from old: Any, to new: Any, area: AnalyticsSettingArea, display: AnalyticsDisplayRole? = nil) {
        guard acceptsEvents else { return }
        for change in AnalyticsSettingChange.changes(from: old, to: new) {
            let key = "\(area.rawValue).\(display?.rawValue ?? "").\(change.identity)"
            let merged = settingChanges[key].map { change.following($0.change) } ?? change
            settingChanges[key] = PendingSettingChange(change: merged, area: area, display: display)
        }
        settingFlush?.cancel()
        settingFlush = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.flushSettingChanges()
        }
        contextDidChange()
    }

    /// Asks for the registered context to be recomputed soon. Cheap to call repeatedly.
    func contextDidChange() {
        guard backendStarted, contextRefresh == nil else { return }
        contextRefresh = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            contextRefresh = nil
            refreshContext()
        }
    }

    // MARK: - Lifecycle

    /// Begins observing system appearance and accessibility changes and starts the backend if
    /// consent already allows it. Call once at launch, after ``contextInputs`` is set.
    func start() {
        guard maintenance == nil else { return }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.contextDidChange() } })
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.contextDidChange() }
        }
        // One coarse timer: it writes changed counters and sends the summary when a day has passed.
        maintenance = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard let self, !Task.isCancelled else { return }
                counters.persist()
                sendSummaryIfDue()
            }
        }
        activateIfAllowed()
    }

    /// Sends the final summary, hands queued events to the backend, and stops observing.
    /// Call from `applicationWillTerminate`.
    func stop() {
        maintenance?.cancel()
        maintenance = nil
        settingFlush?.cancel()
        contextRefresh?.cancel()
        contextRefresh = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        appearanceObservation = nil
        if backendStarted {
            flushSettingChanges()
            sendSummary()
            let records = takePendingRecords()
            // The process is about to exit, so wait for the hand-off. Events the SDK cannot
            // upload in time stay in its disk queue and go out on the next launch.
            queue.sync { [backend] in
                records.forEach(backend.capture)
                backend.flush()
            }
        }
        counters.persist()
    }

    // MARK: - Consent

    /// Records that the notice was on screen and releases anything that was waiting for it.
    func noticeShown() {
        if consent.markNoticeShown() { activateIfAllowed() }
    }

    /// Turning sharing off stops collection at once and deletes everything not yet uploaded.
    func setSharingEnabled(_ enabled: Bool) {
        guard enabled != consent.record.sharingEnabled else { return }
        consent.setSharingEnabled(enabled)
        if enabled { activateIfAllowed() } else { deactivate() }
    }

    func setPersonProfilesEnabled(_ enabled: Bool) {
        guard enabled != consent.record.personProfilesEnabled else { return }
        consent.setPersonProfilesEnabled(enabled)
        guard backendStarted else { return }
        queue.async { [backend] in backend.setPersonProfiles(enabled) }
        if enabled { sendPersonProperties() }
    }

    /// Replaces the anonymous ID. Later events are not connected to earlier ones.
    func resetAnonymousID() {
        guard backendStarted else { return }
        queue.async { [backend] in backend.resetIdentity() }
        // The SDK forgets registered properties with the identity, so register them again.
        registered = AnalyticsProperties()
        refreshContext()
    }

    // MARK: - Internals

    private var buildMaySend: Bool {
        #if DEBUG
        debugSendingEnabled
        #else
        true
        #endif
    }

    /// Whether events are worth keeping: either they can be sent now, or a new user may still
    /// see the notice during this launch.
    private var acceptsEvents: Bool { isConfigured && buildMaySend && consent.record.sharingEnabled }

    private func activateIfAllowed() {
        guard !backendStarted, isConfigured, buildMaySend, consent.allowsCollection else { return }
        backend.start(personProfiles: consent.record.personProfilesEnabled)
        backendStarted = true
        refreshContext()
        sendSummaryIfDue()
        scheduleDrain()
    }

    private func deactivate() {
        pending.removeAll()
        settingChanges.removeAll()
        settingFlush?.cancel()
        contextRefresh?.cancel()
        contextRefresh = nil
        counters.discard()
        registered = AnalyticsProperties()
        guard backendStarted else { return }
        backendStarted = false
        queue.async { [backend] in backend.stopAndDiscard() }
    }

    private func scheduleDrain() {
        guard backendStarted, !drainScheduled, !pending.isEmpty else { return }
        drainScheduled = true
        Task { [weak self] in
            await Task.yield()
            self?.drain()
        }
    }

    private func drain() {
        drainScheduled = false
        guard backendStarted else { return }
        let records = takePendingRecords()
        guard !records.isEmpty else { return }
        queue.async { [backend] in records.forEach(backend.capture) }
    }

    private func takePendingRecords() -> [AnalyticsRecord] {
        defer { pending.removeAll(keepingCapacity: true) }
        return pending.map(\.record)
    }

    private func flushSettingChanges() {
        settingFlush = nil
        let changes = settingChanges.values.filter { $0.change.oldValue != $0.change.newValue }
        settingChanges.removeAll()
        for item in changes { track(.settingChanged(item.change, area: item.area, display: item.display)) }
    }

    /// Registers what changed in the context and removes keys that no longer apply, such as
    /// those of a display that was unplugged.
    private func refreshContext() {
        guard backendStarted, let inputs = contextInputs?() else { return }
        let current = AnalyticsContext.superProperties(inputs)
        let changed = current.changes(from: registered)
        let removed = registered.keys(missingFrom: current)
        registered = current
        guard !changed.isEmpty || !removed.isEmpty else { return }
        queue.async { [backend] in
            backend.unregister(removed)
            backend.register(changed)
        }
        sendPersonProperties()
    }

    private func sendPersonProperties() {
        guard backendStarted, consent.record.personProfilesEnabled, let inputs = contextInputs?() else { return }
        let properties = AnalyticsContext.personProperties(inputs)
        queue.async { [backend] in backend.setPersonProperties(properties) }
    }

    private func sendSummaryIfDue() {
        guard Date().timeIntervalSince(counters.since) >= Self.summaryInterval else { return }
        sendSummary()
    }

    /// Sends the counters with the current per-display counts and refreshes the person profile.
    private func sendSummary() {
        guard backendStarted else { return }
        var properties = counters.drain()
        if let inputs = contextInputs?() { properties.merge(AnalyticsContext.summaryProperties(inputs)) }
        track(.usageSummary(properties))
        refreshContext()
        sendPersonProperties()
    }
}
