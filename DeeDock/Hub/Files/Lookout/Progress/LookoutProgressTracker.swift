import Foundation

/// Turns the engine's status and the index service's into `LookoutProgressDisplay`, remembering what a single status
/// can't say: where the current pass started and how fast it goes. `LookoutEngine` feeds it every status, also the
/// ones it doesn't publish, so the pace sees every step. Pure, so phases, passes and estimates are testable without
/// the service.
///
/// The pass: it starts when files wait while none did, with what the index had settled then as its start, so it
/// counts only its own files. An index that has never been up to date (`LookoutIndexStatus.upToDateAt` is nil) is
/// still in its first pass, which counts from the start, also when DOKK relaunched partway. The pass ends when
/// Lookout is up to date (or waits only for a drive), which also resets the pace.
///
/// What the fields mean for each phase:
/// - Counting: `total` is how many files the walk has found so far (`LookoutIndexStatus.discovered`), else what
///   the index already knows; it isn't final. `remaining` is nil during the first walk.
/// - Reading, paused, failed: `done` and `total` are the pass's, and `total` is final.
/// - Up to date, and waiting for a drive: `done` and `total` are every file the index knows in the folders that are
///   there. Waiting for a drive, `remaining` is nil: how many files the missing drive holds isn't counted.
nonisolated struct LookoutProgressTracker: Equatable, Sendable {
    /// Files settled when the pass started; nil between passes.
    private var passStart: Int?
    /// Files read per second while reading files.
    private(set) var files = LookoutRateEstimator()
    /// Pages and chunks read per second while finishing long files (`LookoutIndexStatus.done`).
    private(set) var steps = LookoutRateEstimator()

    init() {}

    /// The progress for the engine's `status` and the service's latest `index` status at `now`.
    ///
    /// - Parameters:
    ///   - status: The engine's status (`LookoutStatus.map`), which already says why reading waits or failed.
    ///   - index: The index service's latest status; nil before the first one arrives.
    /// - Returns: Nil while Lookout isn't set up or is off, and while it waits for the model: Settings' progress card
    ///   has nothing to track then, and the download shows in the Files tab's card and chip instead.
    mutating func progress(status: LookoutStatus, index: LookoutIndexStatus?, now: Date) -> LookoutProgressDisplay? {
        switch status {
        case .notSetUp, .off:
            self = LookoutProgressTracker()
            return nil
        case .waitingForModel:
            files.pause()
            steps.pause()
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
        if phase == .reading, let index {
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

        let passDone = passStart.map { settled - $0 } ?? 0
        let done: Int, total: Int?, totalIsFinal: Bool, remaining: Int?
        switch phase {
        case .upToDate:
            (done, total, totalIsFinal, remaining) = (counts.files, counts.files, true, 0)
        case .waitingForDrive:
            (done, total, totalIsFinal, remaining) = (counts.files, counts.files, true, nil)
        case .counting:
            let found = index?.discovered ?? (counts.files > 0 ? counts.files : nil)
            (done, total, totalIsFinal, remaining) = (passDone, found, false, counts.files > 0 ? waiting : nil)
        case .reading, .paused, .failed:
            (done, total, totalIsFinal, remaining) = (passDone, passDone + waiting, true, waiting)
        }

        var filesPerSecond: Double?
        var estimate: TimeInterval?
        if phase == .reading, let index {
            if index.activity == .finishingLongFiles {
                estimate = steps.timeRemaining(for: max(index.total - index.done, 0))
            } else {
                filesPerSecond = files.unitsPerSecond
                // The files waiting; long files' later pages follow at their own pace once these are read.
                estimate = files.timeRemaining(for: counts.pending)
            }
        }

        return LookoutProgressDisplay(
            phase: phase, done: done, total: total, totalIsFinal: totalIsFinal, remaining: remaining,
            filesPerSecond: filesPerSecond, estimatedRemaining: estimate, kinds: Self.kinds(counts),
            lastCompleted: index?.upToDateAt, skipped: counts.skipped, failed: counts.failed,
            problems: Self.problems(counts))
    }

    /// The phase: failures and pauses as the engine's status says; then walking, reading, and up to date (or waiting
    /// for a drive) as the service says. `progress` handles the statuses with no phase (not set up, off, waiting for
    /// the model) before it asks.
    static func phase(status: LookoutStatus, index: LookoutIndexStatus?) -> LookoutProgressDisplay.Phase {
        switch status {
        case .failed(let failure): return .failed(message: failure.message)
        case .paused(let reason): return .paused(reason: .init(reason))
        case .indexing:
            guard let index, index.activity != .syncing else { return .counting }
            return .reading
        case .ready:
            if let missing = index?.missingRoots.first { return .waitingForDrive(name: driveName(of: missing)) }
            return .upToDate
        case .notSetUp, .off, .waitingForModel:
            return .counting
        }
    }

    /// The name of the drive a missing folder is on (`/Volumes/Photos/2024` → "Photos"), or the folder's own name.
    static func driveName(of path: String) -> String {
        let components = (path as NSString).pathComponents
        if components.count >= 3, components[0] == "/", components[1] == "Volumes" { return components[2] }
        return (path as NSString).lastPathComponent
    }

    private static func kinds(_ counts: IndexStore.Counts) -> [FileKind: LookoutProgressDisplay.KindProgress] {
        var kinds: [FileKind: LookoutProgressDisplay.KindProgress] = [:]
        for (raw, states) in counts.byKindAndState {
            guard let kind = FileKind(rawValue: raw) else { continue }
            let total = states.values.reduce(0, +)
            guard total > 0 else { continue }
            let waiting = (states["pending"] ?? 0) + (states["partial"] ?? 0)
            kinds[kind] = LookoutProgressDisplay.KindProgress(done: total - waiting, total: total)
        }
        return kinds
    }

    /// Skipped and failed files by why, most first, with each reason in the app's language.
    private static func problems(_ counts: IndexStore.Counts) -> [LookoutProgressDisplay.Problem] {
        let reasons = (counts.problems ?? [:]).compactMap { raw, count -> (LookoutProblemReason, Int)? in
            guard let reason = LookoutProblemReason(rawValue: raw), count > 0 else { return nil }
            return (reason, count)
        }
        return reasons.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.rawValue < $1.0.rawValue }
            .map { LookoutProgressDisplay.Problem(reason: String(localized: $0.0.title), count: $0.1) }
    }
}

extension LookoutProgressDisplay.PauseReason {
    /// The display's reason for the engine's.
    nonisolated init(_ reason: LookoutPauseReason) {
        switch reason {
        case .lowPowerMode: self = .lowPowerMode
        case .warm: self = .thermal
        case .onBattery: self = .onBattery
        case .user: self = .userPaused
        }
    }
}
