import Foundation

/// Deterministic progress for previews of whatever shows it: every phase a person meets, with numbers that read like
/// a real first pass over Desktop, Documents and Downloads. Nothing here touches the engine or the index service.
nonisolated enum LookoutProgressPreviewData {
    /// 12 Oct 2026, 09:30 UTC: "last up to date" reads the same in every preview.
    static let lastCompleted = Date(timeIntervalSince1970: 1_791_797_400)

    /// The first walk, a few seconds in: 1,750 files found so far, and still counting.
    static let stillCounting = LookoutProgress(
        phase: .counting, done: 0, total: 1_750, totalIsFinal: false, remaining: nil, filesPerSecond: nil,
        estimatedRemaining: nil, kinds: [:], lastCompleted: nil, skipped: 0, failed: 0, problems: [])

    /// The first pass just started: files are going by, but it's too early for a pace or a time.
    static let runningEarly = LookoutProgress(
        phase: .reading, done: 12, total: 4_812, totalIsFinal: true, remaining: 4_800, filesPerSecond: nil,
        estimatedRemaining: nil,
        kinds: kinds(screenshots: (12, 640), images: (0, 2_310), pdfs: (0, 905), documents: (0, 957)),
        lastCompleted: nil, skipped: 0, failed: 0, problems: [])

    /// The first pass halfway, with a steady pace and about 17 minutes left.
    static let runningWithEstimate = LookoutProgress(
        phase: .reading, done: 2_410, total: 4_812, totalIsFinal: true, remaining: 2_402, filesPerSecond: 2.4,
        estimatedRemaining: 1_001,
        kinds: kinds(screenshots: (640, 640), images: (1_528, 2_310), pdfs: (180, 905), documents: (62, 957)),
        lastCompleted: nil, skipped: 18, failed: 2,
        problems: [.init(reason: .tooSmall, count: 14), .init(reason: .noText, count: 4),
                   .init(reason: .unreadable, count: 2)])

    /// Reading waits for Low Power Mode, partway through.
    static let pausedLowPower = LookoutProgress(
        phase: .paused(.lowPowerMode), done: 3_120, total: 4_812, totalIsFinal: true, remaining: 1_692,
        filesPerSecond: nil, estimatedRemaining: nil,
        kinds: kinds(screenshots: (640, 640), images: (2_005, 2_310), pdfs: (320, 905), documents: (155, 957)),
        lastCompleted: nil, skipped: 21, failed: 2,
        problems: [.init(reason: .tooSmall, count: 16), .init(reason: .noText, count: 5),
                   .init(reason: .unreadable, count: 2)])

    /// Everything else is read; the folder on the drive "Photos" isn't connected.
    static let waitingForDrive = LookoutProgress(
        phase: .waitingForDrive(name: "Photos"), done: 4_812, total: 4_812, totalIsFinal: true, remaining: 0,
        filesPerSecond: nil, estimatedRemaining: nil,
        kinds: kinds(screenshots: (640, 640), images: (2_310, 2_310), pdfs: (905, 905), documents: (957, 957)),
        lastCompleted: lastCompleted, skipped: 0, failed: 0, problems: [])

    /// All read, nothing went wrong.
    static let upToDate = LookoutProgress(
        phase: .upToDate, done: 4_812, total: 4_812, totalIsFinal: true, remaining: 0, filesPerSecond: nil,
        estimatedRemaining: nil,
        kinds: kinds(screenshots: (640, 640), images: (2_310, 2_310), pdfs: (905, 905), documents: (957, 957)),
        lastCompleted: lastCompleted, skipped: 0, failed: 0, problems: [])

    /// All read, with files Lookout skipped or couldn't read, by why.
    static let upToDateWithProblems = LookoutProgress(
        phase: .upToDate, done: 4_812, total: 4_812, totalIsFinal: true, remaining: 0, filesPerSecond: nil,
        estimatedRemaining: nil,
        kinds: kinds(screenshots: (640, 640), images: (2_310, 2_310), pdfs: (905, 905), documents: (957, 957)),
        lastCompleted: lastCompleted, skipped: 37, failed: 6,
        problems: [.init(reason: .tooSmall, count: 22), .init(reason: .noText, count: 9),
                   .init(reason: .unreadable, count: 5), .init(reason: .passwordProtected, count: 4),
                   .init(reason: .notDownloaded, count: 2), .init(reason: .other, count: 1)])

    /// Reading stopped partway: the index service failed (its sentence is `LookoutFailure.message`).
    static let readingStopped = LookoutProgress(
        phase: .failed(LookoutFailure(kind: .indexing)), done: 1_204, total: 4_812, totalIsFinal: true,
        remaining: 3_608, filesPerSecond: nil, estimatedRemaining: nil,
        kinds: kinds(screenshots: (640, 640), images: (564, 2_310), pdfs: (0, 905), documents: (0, 957)),
        lastCompleted: nil, skipped: 9, failed: 1,
        problems: [.init(reason: .tooSmall, count: 9), .init(reason: .other, count: 1)])

    /// Every sample, named, for a preview that lists them all.
    static let all: [(name: String, progress: LookoutProgress)] = [
        ("Still counting", stillCounting), ("Running, early", runningEarly),
        ("Running, with estimate", runningWithEstimate), ("Paused, Low Power Mode", pausedLowPower),
        ("Waiting for a drive", waitingForDrive), ("Up to date", upToDate),
        ("Up to date, with problems", upToDateWithProblems), ("Reading stopped", readingStopped),
    ]

    private static func kinds(screenshots: (Int, Int), images: (Int, Int), pdfs: (Int, Int),
                              documents: (Int, Int)) -> [FileKind: LookoutProgress.KindCount] {
        [.screenshot: .init(done: screenshots.0, total: screenshots.1), .image: .init(done: images.0, total: images.1),
         .pdf: .init(done: pdfs.0, total: pdfs.1), .doc: .init(done: documents.0, total: documents.1)]
    }
}
