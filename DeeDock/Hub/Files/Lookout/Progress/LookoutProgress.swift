import Foundation

/// Where Lookout's reading stands, for Settings and anything else that shows progress: what it's doing, how far the
/// current pass has got and how much is left, how fast it goes and about how long the rest takes, what's in the
/// index by kind, when it was last up to date, and what it skipped or couldn't read and why.
///
/// `LookoutEngine.progress` publishes it, at most `LookoutEngine.progressInterval` apart while files go by and at once
/// when the phase changes; it's nil while Lookout isn't set up or is off. `LookoutProgressTracker` derives it from
/// the engine's status and the index service's, so every field is testable without the service.
///
/// A pass starts when files wait to be read and ends when nothing does. `done` and `total` count that pass: a first
/// pass the index hasn't finished yet counts from the start, also after DOKK relaunched, and a later pass (new or
/// changed files) counts only its own files. Up to date, both are every file the index knows.
nonisolated struct LookoutProgress: Equatable, Sendable {
    /// What Lookout is doing.
    enum Phase: Equatable, Sendable {
        /// Walking the chosen folders to find what's new, changed or gone. The first pass's total grows meanwhile
        /// (`totalIsFinal` is false).
        case counting
        /// Reading files: new files, the backfill, or the rest of long PDFs and documents.
        case reading
        /// Everything in the folders that are there is read.
        case upToDate
        /// Reading waits: Low Power Mode, the Mac is warm, on battery with reading on battery off, or the person
        /// paused it. What's read stays searchable.
        case paused(LookoutPauseReason)
        /// Everything else is up to date, but a chosen folder isn't there (an unplugged drive). `name` is the drive's
        /// name, or the folder's when it isn't on a drive of its own. Its files come back when it's connected.
        case waitingForDrive(name: String)
        /// The model files aren't all there yet; names are searchable meanwhile, and nothing is read.
        case waitingForModel
        /// Reading stopped (`LookoutFailure.message` says why).
        case failed(LookoutFailure)
    }

    /// One kind's files: how many the index has read (or settled), of how many it knows.
    struct KindCount: Equatable, Sendable {
        var done: Int
        var total: Int
    }

    /// Files skipped or not read for one reason.
    struct Problem: Equatable, Sendable {
        let reason: LookoutProblemReason
        let count: Int
    }

    var phase: Phase
    /// Files of this pass that are read, or settled otherwise (skipped, failed). Every file the index knows when up
    /// to date.
    var done: Int
    /// The files this pass reads: `done` plus what waits. Nil while the first walk hasn't found anything yet, or
    /// while a later walk hasn't queued anything; it may still grow while `totalIsFinal` is false.
    var total: Int?
    /// Whether `total` is known for good: false while the walk is still counting.
    var totalIsFinal: Bool
    /// Files still to read: waiting, or long files part read. Nil while the first walk is still counting.
    var remaining: Int?
    /// Files read per second, smoothed over about half a minute of reading. Nil until there are enough of them to
    /// say (`LookoutRateEstimator`), and while the later pass reads long files, which go by pages, not files.
    var filesPerSecond: Double?
    /// About how long the rest takes, from the smoothed pace: the files waiting while reading files, or the pages and
    /// chunks left while finishing long files. Nil when it can't be said honestly: too early, not reading, or nothing
    /// left.
    var estimatedRemaining: TimeInterval?
    /// What the index holds by kind, read of known. Only kinds with files.
    var kinds: [FileKind: KindCount]
    /// When the index was last up to date, also from before DOKK started. Nil until that first happens.
    var lastCompleted: Date?
    /// Files Lookout tried and skipped (too small, no text, not downloaded, left out by a rule).
    var skipped: Int
    /// Files Lookout couldn't read.
    var failed: Int
    /// Skipped and failed files by why, most first.
    var problems: [Problem]
}
