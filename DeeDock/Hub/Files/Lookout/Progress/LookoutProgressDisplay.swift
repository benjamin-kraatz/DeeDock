import Foundation

/// Lookout's indexing progress as Settings (and the Hub's chip) show it: what it's doing, how far it is, how much is
/// left, and what it skipped. A plain value, so the progress card can be previewed and tested with no engine.
///
/// It's the one progress type: `LookoutProgressTracker` derives it from the engine's status and the index service's,
/// `LookoutEngine.progress` publishes it (throttled), and `LookoutSettingsModel.progress` and the status chip read it.
/// Deterministic states for previews are in `LookoutProgressDisplay.Sample`.
///
/// Counts are files. `total` is nil until the service has counted anything; while `phase` is `.counting`, or
/// `totalIsFinal` is false, the total still grows and the percentage is only a hint. The tracker documents what each
/// field holds in each phase.
nonisolated struct LookoutProgressDisplay: Equatable, Sendable {
    /// What Lookout is doing right now.
    enum Phase: Equatable, Sendable {
        /// Walking the folders; the total still grows.
        case counting
        /// Reading file contents.
        case reading
        /// Everything that may be read is read.
        case upToDate
        /// Reading waits; what's indexed stays searchable.
        case paused(reason: PauseReason)
        /// A chosen folder lives on a drive that isn't connected; its files wait.
        case waitingForDrive(name: String)
        /// Reading stopped. `message` is the localized explanation.
        case failed(message: String)
    }

    /// Why reading waits.
    enum PauseReason: Equatable, Sendable {
        case lowPowerMode
        /// Thermal state serious or critical.
        case thermal
        /// On battery with "Read files on battery too" off.
        case onBattery
        /// The person paused it.
        case userPaused
    }

    /// One kind's files read out of all of that kind.
    struct KindProgress: Equatable, Sendable {
        var done: Int
        var total: Int

        init(done: Int, total: Int) {
            self.done = done
            self.total = total
        }
    }

    /// Why some files were skipped or couldn't be read, and how many.
    struct Problem: Equatable, Sendable, Identifiable {
        /// The reason in the app's language (`LookoutProblemReason.title`: "Too large to read", "Couldn't be read").
        var reason: String
        var count: Int

        var id: String { reason }

        init(reason: String, count: Int) {
            self.reason = reason
            self.count = count
        }
    }

    var phase: Phase
    /// Files of this pass read (done, skipped or failed: anything no longer waiting); every file the index knows once
    /// it's up to date.
    var done: Int
    /// The files this pass reads (every file the index knows once up to date); while counting, the files found so
    /// far. Nil before anything is counted.
    var total: Int?
    /// The folders have been walked, so `total` won't grow in this pass.
    var totalIsFinal: Bool
    /// Files still waiting; nil when not known.
    var remaining: Int?
    /// The reading rate, when it's steady enough to show.
    var filesPerSecond: Double?
    /// Seconds until the pass ends; nil until the rate is meaningful, and whenever Lookout isn't reading.
    var estimatedRemaining: TimeInterval?
    /// Per-kind progress; empty when the service doesn't break it down.
    var kinds: [FileKind: KindProgress]
    /// When the index was last up to date, also from before DOKK started.
    var lastCompleted: Date?
    /// Files Lookout chose not to read (too large, a kind it doesn't read in full).
    var skipped: Int
    /// Files it tried and couldn't read.
    var failed: Int
    /// The reasons behind `skipped` and `failed`, largest first.
    var problems: [Problem]

    init(phase: Phase, done: Int = 0, total: Int? = nil, totalIsFinal: Bool = false, remaining: Int? = nil,
         filesPerSecond: Double? = nil, estimatedRemaining: TimeInterval? = nil,
         kinds: [FileKind: KindProgress] = [:], lastCompleted: Date? = nil, skipped: Int = 0, failed: Int = 0,
         problems: [Problem] = []) {
        self.phase = phase
        self.done = done
        self.total = total
        self.totalIsFinal = totalIsFinal
        self.remaining = remaining
        self.filesPerSecond = filesPerSecond
        self.estimatedRemaining = estimatedRemaining
        self.kinds = kinds
        self.lastCompleted = lastCompleted
        self.skipped = skipped
        self.failed = failed
        self.problems = problems
    }

    // MARK: Derived

    /// 0…1 through the pass; nil before there's a total. Reaches 1 only when nothing is left, so a pass that is
    /// 99.6 % through doesn't read as complete (`LookoutProgressFormatting.percent` rounds the same way).
    var fraction: Double? {
        if phase == .upToDate { return 1 }
        guard let total, total > 0 else { return nil }
        return min(max(Double(done) / Double(total), 0), 1)
    }

    /// The pass is still going: counting or reading.
    var isActive: Bool {
        switch phase {
        case .counting, .reading: true
        case .upToDate, .paused, .waitingForDrive, .failed: false
        }
    }

    /// Something was skipped or couldn't be read.
    var hasProblems: Bool { skipped + failed > 0 }
}
