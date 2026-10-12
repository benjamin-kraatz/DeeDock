import Foundation

/// Turns the engine's status and the index service's into `LookoutProgress`, remembering what a single status can't
/// say: where the current pass started and how fast it goes. `LookoutEngine` feeds it every status, also the ones it
/// doesn't publish, so the pace sees every step. Pure, so phases, passes and estimates are testable without the
/// service.
///
/// The pass: it starts when files wait while none did, with what the index had settled then as its start, so it
/// counts only its own files. An index that has never been up to date (`LookoutIndexStatus.upToDateAt` is nil) is
/// still in its first pass, which counts from the start, also when DOKK relaunched partway. The pass ends when
/// Lookout is up to date (or waits only for a drive), which also resets the pace.
nonisolated struct LookoutProgressTracker: Equatable, Sendable {
    /// Files settled when the pass started; nil between passes.
    private var passStart: Int?
    /// Files read per second while reading files.
    private(set) var files = LookoutRateEstimator()
    /// Pages and chunks read per second while finishing long files (`LookoutIndexStatus.done`).
    private(set) var steps = LookoutRateEstimator()

    init() {}

    /// The progress for the engine's `status` and the service's latest `index` status at `now`, or nil while Lookout
    /// isn't set up or is off.
    ///
    /// - Parameters:
    ///   - status: The engine's status (`LookoutStatus.map`), which already says why reading waits or failed.
    ///   - index: The index service's latest status; nil before the first one arrives.
    mutating func progress(status: LookoutStatus, index: LookoutIndexStatus?, now: Date) -> LookoutProgress? {
        switch status {
        case .notSetUp, .off:
            self = LookoutProgressTracker()
            return nil
        default:
            break
        }
        let counts = index?.counts ?? IndexStore.Counts()
        let waiting = counts.pending + counts.unfinished
        let settled = max(counts.files - waiting, 0)
        let phase = Self.phase(status: status, index: index)

        // Where the pass started.
        switch phase {
        case .upToDate, .waitingForDrive:
            passStart = nil
        default:
            if passStart == nil, waiting > 0 { passStart = index?.upToDateAt == nil ? 0 : settled }
        }
        // Files that left the index (deleted, or their folder removed) can't make the pass go backwards.
        if let start = passStart, settled < start { passStart = settled }

        // The pace: only reading counts.
        if case .reading = phase, let index {
            if index.activity == .finishingLongFiles {
                files.pause()
                steps.record(index.done, at: now)
            } else {
                steps.pause()
                files.record(settled, at: now)
            }
        } else if passStart == nil {
            files.reset()
            steps.reset()
        } else {
            files.pause()
            steps.pause()
        }

        let done: Int, total: Int?, totalIsFinal: Bool, remaining: Int?
        switch phase {
        case .upToDate, .waitingForDrive:
            (done, total, totalIsFinal, remaining) = (counts.files, counts.files, true, 0)
        case .counting where counts.files == 0:
            // The first walk: everything it finds will be read.
            (done, total, totalIsFinal, remaining) = (0, index?.discovered, false, nil)
        case .counting:
            let passDone = passStart.map { settled - $0 } ?? 0
            (done, total, totalIsFinal, remaining) = (passDone, passStart == nil ? nil : passDone + waiting, false,
                                                      waiting)
        default:
            let passDone = passStart.map { settled - $0 } ?? 0
            (done, total, totalIsFinal, remaining) = (passDone, passDone + waiting, true, waiting)
        }

        var filesPerSecond: Double?
        var estimate: TimeInterval?
        if case .reading = phase, let index {
            if index.activity == .finishingLongFiles {
                estimate = steps.timeRemaining(for: max(index.total - index.done, 0))
            } else {
                filesPerSecond = files.unitsPerSecond
                // The files waiting; long files' later pages follow at their own pace once these are read.
                estimate = files.timeRemaining(for: counts.pending)
            }
        }

        return LookoutProgress(
            phase: phase, done: done, total: total, totalIsFinal: totalIsFinal, remaining: remaining,
            filesPerSecond: filesPerSecond, estimatedRemaining: estimate, kinds: Self.kinds(counts),
            lastCompleted: index?.upToDateAt, skipped: counts.skipped, failed: counts.failed,
            problems: Self.problems(counts))
    }

    /// The phase: failures, the model, and pauses as the engine's status says; then walking, reading, and up to date
    /// (or waiting for a drive) as the service says.
    static func phase(status: LookoutStatus, index: LookoutIndexStatus?) -> LookoutProgress.Phase {
        switch status {
        case .failed(let failure): return .failed(failure)
        case .waitingForModel: return .waitingForModel
        case .paused(let reason): return .paused(reason)
        case .indexing:
            guard let index, index.activity != .syncing else { return .counting }
            return .reading
        case .ready:
            if let missing = index?.missingRoots.first { return .waitingForDrive(name: driveName(of: missing)) }
            return .upToDate
        case .notSetUp, .off:
            return .upToDate
        }
    }

    /// The name of the drive a missing folder is on (`/Volumes/Photos/2024` → "Photos"), or the folder's own name.
    static func driveName(of path: String) -> String {
        let components = (path as NSString).pathComponents
        if components.count >= 3, components[0] == "/", components[1] == "Volumes" { return components[2] }
        return (path as NSString).lastPathComponent
    }

    private static func kinds(_ counts: IndexStore.Counts) -> [FileKind: LookoutProgress.KindCount] {
        var kinds: [FileKind: LookoutProgress.KindCount] = [:]
        for (raw, states) in counts.byKindAndState {
            guard let kind = FileKind(rawValue: raw) else { continue }
            let total = states.values.reduce(0, +)
            guard total > 0 else { continue }
            let waiting = (states["pending"] ?? 0) + (states["partial"] ?? 0)
            kinds[kind] = LookoutProgress.KindCount(done: total - waiting, total: total)
        }
        return kinds
    }

    private static func problems(_ counts: IndexStore.Counts) -> [LookoutProgress.Problem] {
        (counts.problems ?? [:]).compactMap { raw, count in
            LookoutProblemReason(rawValue: raw).map { LookoutProgress.Problem(reason: $0, count: count) }
        }
        .filter { $0.count > 0 }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.reason.rawValue < $1.reason.rawValue }
    }
}
