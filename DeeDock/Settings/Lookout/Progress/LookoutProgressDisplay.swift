import Foundation

/// Lookout's indexing progress as Settings (and the Hub's chip) show it: what it's doing, how far it is, how much is
/// left, and what it skipped. A plain value, so the progress card can be previewed and tested with no engine; the
/// engine side maps its status into one of these (`LookoutSettingsModel.progress`).
///
/// Counts are files. `total` is nil until the service has counted anything; while `phase` is `.counting`, or
/// `totalIsFinal` is false, the total still grows and the percentage is only a hint.
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
        /// The localized reason ("Too large", "Couldn't be opened").
        var reason: String
        var count: Int

        var id: String { reason }

        init(reason: String, count: Int) {
            self.reason = reason
            self.count = count
        }
    }

    var phase: Phase
    /// Files read (done, skipped or failed: anything no longer waiting).
    var done: Int
    /// Every file Lookout knows; nil before it has counted anything.
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
    /// When the last pass finished.
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

// MARK: - Samples

extension LookoutProgressDisplay {
    /// Fixed states for previews and renders. Dates are relative to `now` so "finished 10:41" stays today.
    enum Sample {
        private static let kinds: [FileKind: KindProgress] = [
            .image: KindProgress(done: 1_204, total: 2_310),
            .screenshot: KindProgress(done: 611, total: 640),
            .pdf: KindProgress(done: 318, total: 1_402),
            .doc: KindProgress(done: 1_077, total: 850 + 1_077),
        ]

        /// Still walking the folders: no final total, no rate.
        static let counting = LookoutProgressDisplay(
            phase: .counting, done: 0, total: 1_860, totalIsFinal: false, remaining: nil,
            kinds: [.image: KindProgress(done: 0, total: 1_120), .screenshot: KindProgress(done: 0, total: 212),
                    .pdf: KindProgress(done: 0, total: 318), .doc: KindProgress(done: 0, total: 210)])

        /// Just started reading: the rate isn't steady yet, so no time left.
        static let readingEarly = LookoutProgressDisplay(
            phase: .reading, done: 96, total: 5_202, totalIsFinal: true, remaining: 5_106,
            kinds: [.image: KindProgress(done: 64, total: 2_310), .screenshot: KindProgress(done: 32, total: 640),
                    .pdf: KindProgress(done: 0, total: 1_402), .doc: KindProgress(done: 0, total: 850)])

        /// Mid-pass, with a rate and an estimate.
        static let readingMid = LookoutProgressDisplay(
            phase: .reading, done: 3_210, total: 5_202, totalIsFinal: true, remaining: 1_992,
            filesPerSecond: 5.4, estimatedRemaining: 369, kinds: kinds, skipped: 12, failed: 3,
            problems: [Problem(reason: "Larger than 200 MB", count: 9), Problem(reason: "Couldn't be opened", count: 3),
                       Problem(reason: "Encrypted PDF", count: 3)])

        /// A big index, hours in.
        static let big = LookoutProgressDisplay(
            phase: .reading, done: 31_880, total: 48_213, totalIsFinal: true, remaining: 16_333,
            filesPerSecond: 3.1, estimatedRemaining: 5_268,
            kinds: [.image: KindProgress(done: 18_402, total: 24_110), .screenshot: KindProgress(done: 4_210, total: 4_300),
                    .pdf: KindProgress(done: 3_968, total: 11_803), .doc: KindProgress(done: 5_300, total: 8_000)],
            skipped: 41, failed: 7,
            problems: [Problem(reason: "Larger than 200 MB", count: 38), Problem(reason: "Couldn't be opened", count: 7),
                       Problem(reason: "Encrypted PDF", count: 3)])

        /// Low Power Mode holds the pass.
        static let pausedLowPower = LookoutProgressDisplay(
            phase: .paused(reason: .lowPowerMode), done: 3_210, total: 5_202, totalIsFinal: true, remaining: 1_992,
            kinds: kinds, skipped: 12, failed: 3,
            problems: [Problem(reason: "Larger than 200 MB", count: 9), Problem(reason: "Couldn't be opened", count: 3),
                       Problem(reason: "Encrypted PDF", count: 3)])

        /// The person paused it.
        static let pausedByUser = LookoutProgressDisplay(
            phase: .paused(reason: .userPaused), done: 3_210, total: 5_202, totalIsFinal: true, remaining: 1_992,
            kinds: kinds)

        /// A folder on an unplugged drive.
        static let waitingForDrive = LookoutProgressDisplay(
            phase: .waitingForDrive(name: "Backup Drive"), done: 4_980, total: 5_202, totalIsFinal: true,
            remaining: 222,
            kinds: [.image: KindProgress(done: 2_310, total: 2_310), .screenshot: KindProgress(done: 640, total: 640),
                    .pdf: KindProgress(done: 1_180, total: 1_402), .doc: KindProgress(done: 850, total: 850)])

        /// Done, this morning.
        static func upToDate(now: Date = .now) -> LookoutProgressDisplay {
            let calendar = Calendar.current
            let finished = calendar.date(bySettingHour: 10, minute: 41, second: 0, of: now) ?? now
            return LookoutProgressDisplay(
                phase: .upToDate, done: 5_202, total: 5_202, totalIsFinal: true, remaining: 0,
                kinds: [.image: KindProgress(done: 2_310, total: 2_310), .screenshot: KindProgress(done: 640, total: 640),
                        .pdf: KindProgress(done: 1_402, total: 1_402), .doc: KindProgress(done: 850, total: 850)],
                lastCompleted: finished, skipped: 12, failed: 3,
                problems: [Problem(reason: "Larger than 200 MB", count: 9), Problem(reason: "Couldn't be opened", count: 3),
                           Problem(reason: "Encrypted PDF", count: 3)])
        }

        /// Reading stopped.
        static let failed = LookoutProgressDisplay(
            phase: .failed(message: "Lookout can't write its index. Check the free space on this Mac."),
            done: 3_210, total: 5_202, totalIsFinal: true, remaining: 1_992, kinds: kinds, skipped: 12, failed: 3,
            problems: [Problem(reason: "Larger than 200 MB", count: 9), Problem(reason: "Couldn't be opened", count: 3),
                       Problem(reason: "Encrypted PDF", count: 3)])

        /// Every sample by a stable name, for renders.
        static func all(now: Date = .now) -> [(name: String, display: LookoutProgressDisplay)] {
            [("counting", counting), ("reading-early", readingEarly), ("reading-mid", readingMid), ("big", big),
             ("paused-low-power", pausedLowPower), ("paused-user", pausedByUser),
             ("waiting-drive", waitingForDrive), ("up-to-date", upToDate(now: now)), ("failed", failed)]
        }
    }
}
