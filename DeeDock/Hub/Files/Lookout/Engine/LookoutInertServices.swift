import Foundation

/// Stand-ins that do nothing, for an engine that must never run: previews, the test host, and a process without a
/// bundle identifier. They open no XPC connection, start no FSEvents stream or observer, and touch no file.
@MainActor final class LookoutInertIndexConnection: LookoutIndexControlling {
    var onStatus: ((LookoutIndexStatus) -> Void)?
    var onConnectionEvent: ((LookoutIndexConnectionEvent) -> Void)?
    var isServiceRunning: Bool { false }
    func start(_ configuration: LookoutIndexConfiguration) {}
    func syncNow() {}
    func setBackfillAllowed(_ allowed: Bool) {}
    func pause() {}
    func resume() {}
    func invalidate() {}
    func resetIndex() {}
    func closeIndex(timeout: Duration) async throws {}
}

/// Never warm; every embed fails, so search stays keyword-only and a picture finds nothing.
@MainActor final class LookoutInertQueryEncoder: LookoutQueryEncoding {
    var isWarm: Bool { false }
    func warmUp() async throws { throw LookoutEncoderError.unavailable }
    func embed(query: String) async throws -> [Float] { throw LookoutEncoderError.unavailable }
    func invalidate() {}
}

/// No index: every search is unavailable.
nonisolated struct LookoutInertIndexReader: LookoutIndexSearching {
    func search(_ request: LookoutSearchRequest) async throws -> LookoutResultSet? { nil }
    func prepareVectors() async {}
    func releaseVectors() async {}
    func indexDidChange() async {}
    func closeIndex() async {}
    func searchableFileCounts(under folders: [String]) async -> [String: Int] { [:] }
    func similar(_ request: LookoutSimilarRequest) async throws -> LookoutSimilarResults? { nil }
    func similarSource(path: String, segmentID: Int64?) async -> LookoutSimilarSource? { nil }
    func indexedPaths(_ paths: [String]) async -> Set<String> { [] }
}

@MainActor final class LookoutInertMonitor: LookoutMonitoring {
    func start(roots: [String], onEvent: @escaping (LookoutMonitorEvent) -> Void) {}
    func watch(roots: [String]) {}
    func stop() {}
}

@MainActor final class LookoutInertPowerPolicy: LookoutPowerPolicing {
    var blocker: LookoutBackfillBlocker? { nil }
    func start(indexOnBattery: Bool, onChange: @escaping (LookoutBackfillBlocker?) -> Void) {}
    func setIndexOnBattery(_ indexOnBattery: Bool) {}
    func stop() {}
}
