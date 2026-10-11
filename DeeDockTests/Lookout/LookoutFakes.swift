import Foundation
@testable import DeeDock

/// Records what the engine asks of the index service, and lets a test play the service's side: statuses,
/// interruptions, a process that exited.
@MainActor final class FakeIndexConnection: LookoutIndexControlling {
    enum Call: Equatable {
        case start(LookoutIndexConfiguration)
        case syncNow, pause, resume, invalidate
        case setBackfillAllowed(Bool)
    }

    var onStatus: ((LookoutIndexStatus) -> Void)?
    var onConnectionEvent: ((LookoutIndexConnectionEvent) -> Void)?
    var isServiceRunning = false
    private(set) var calls: [Call] = []

    func start(_ configuration: LookoutIndexConfiguration) {
        calls.append(.start(configuration))
        isServiceRunning = true
    }

    func syncNow() {
        calls.append(.syncNow)
        isServiceRunning = true
    }

    func setBackfillAllowed(_ allowed: Bool) { calls.append(.setBackfillAllowed(allowed)) }
    func pause() { calls.append(.pause) }

    func resume() {
        calls.append(.resume)
        isServiceRunning = true
    }

    func invalidate() {
        calls.append(.invalidate)
        isServiceRunning = false
    }

    func clearCalls() { calls.removeAll() }

    /// The service reports `status`.
    func send(_ status: LookoutIndexStatus) { onStatus?(status) }

    /// The service process ended.
    func interrupt() {
        isServiceRunning = false
        onConnectionEvent?(.interrupted)
    }

    var configurations: [LookoutIndexConfiguration] {
        calls.compactMap { if case .start(let configuration) = $0 { configuration } else { nil } }
    }
}

/// A query encoder with a chosen delay, warmth and outcome.
@MainActor final class FakeQueryEncoder: LookoutQueryEncoding {
    var isWarm = true
    var delay: Duration = .zero
    var delays: [String: Duration] = [:]
    var fails = false
    private(set) var embedded: [String] = []
    private(set) var warmUps = 0

    func warmUp() async throws {
        warmUps += 1
        isWarm = true
    }

    func embed(query: String) async throws -> [Float] {
        embedded.append(query)
        try await Task.sleep(for: delays[query] ?? delay)
        if fails { throw LookoutEncoderError.service("no model") }
        return LookoutSearchIndex.query
    }

    func invalidate() {}
}

/// An index reader that answers with an empty result set naming the query (`terms == [text]`) and whether a vector
/// came with it, after a chosen delay per query and pass.
actor FakeIndexReader: LookoutIndexSearching {
    private(set) var requests: [LookoutSearchRequest] = []
    private(set) var prepared = 0
    private(set) var released = 0
    private(set) var changes = 0
    private var keywordDelays: [String: Duration] = [:]
    private var available = true

    func setKeywordDelay(_ delay: Duration, for text: String) { keywordDelays[text] = delay }
    func setAvailable(_ available: Bool) { self.available = available }

    func search(_ request: LookoutSearchRequest) async throws -> LookoutResultSet? {
        requests.append(request)
        if request.vector == nil, request.prefixLast, let delay = keywordDelays[request.text] {
            try? await Task.sleep(for: delay)
        }
        guard available else { return nil }
        return LookoutResultSet(ranked: [], terms: [request.text], isLookup: false, usedMeaning: request.vector != nil)
    }

    func prepareVectors() { prepared += 1 }
    func releaseVectors() { released += 1 }
    func indexDidChange() { changes += 1 }
}

@MainActor final class FakeMonitor: LookoutMonitoring {
    private(set) var startedRoots: [String]?
    private(set) var watched: [[String]] = []
    private(set) var stopped = 0
    private var onEvent: ((LookoutMonitorEvent) -> Void)?

    func start(roots: [String], onEvent: @escaping (LookoutMonitorEvent) -> Void) {
        startedRoots = roots
        self.onEvent = onEvent
    }

    func watch(roots: [String]) { watched.append(roots) }

    func stop() {
        stopped += 1
        onEvent = nil
    }

    func emit(_ event: LookoutMonitorEvent) { onEvent?(event) }
}

@MainActor final class FakePowerPolicy: LookoutPowerPolicing {
    var blocker: LookoutBackfillBlocker?
    private(set) var indexOnBattery: Bool?
    private var onChange: ((LookoutBackfillBlocker?) -> Void)?

    func start(indexOnBattery: Bool, onChange: @escaping (LookoutBackfillBlocker?) -> Void) {
        self.indexOnBattery = indexOnBattery
        self.onChange = onChange
    }

    func setIndexOnBattery(_ indexOnBattery: Bool) { self.indexOnBattery = indexOnBattery }
    func stop() { onChange = nil }

    func emit(_ blocker: LookoutBackfillBlocker?) {
        self.blocker = blocker
        onChange?(blocker)
    }
}

/// Waits until `condition` holds, polling every few milliseconds, for at most `timeout`.
@MainActor func eventually(timeout: Duration = .seconds(3), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}
