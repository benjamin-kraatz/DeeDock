import Foundation

extension LookoutProgressDisplay {
    /// Fixed states for previews, renders and tests, shaped as `LookoutProgressTracker` produces them: no per-kind
    /// counts during the first walk, no pace or time left until the pace is steady, the files on a missing drive not
    /// counted, and the reasons for skipped and unreadable files in the app's language. Dates are relative to `now`
    /// so "finished 10:41" stays today. Nothing here touches the engine or the index service.
    nonisolated enum Sample {
        private static func problem(_ reason: LookoutProblemReason, _ count: Int) -> Problem {
            Problem(reason: String(localized: reason.title), count: count)
        }

        private static let kinds: [FileKind: KindProgress] = [
            .image: KindProgress(done: 1_204, total: 2_310),
            .screenshot: KindProgress(done: 611, total: 640),
            .pdf: KindProgress(done: 318, total: 1_402),
            .doc: KindProgress(done: 1_077, total: 850 + 1_077),
        ]

        private static let allRead: [FileKind: KindProgress] = [
            .image: KindProgress(done: 2_310, total: 2_310), .screenshot: KindProgress(done: 640, total: 640),
            .pdf: KindProgress(done: 1_402, total: 1_402), .doc: KindProgress(done: 850, total: 850),
        ]

        /// 9 too small and 3 with no text skipped, 2 unreadable and 1 password-protected.
        private static var someProblems: [Problem] {
            [problem(.tooSmall, 9), problem(.noText, 3), problem(.unreadable, 2), problem(.passwordProtected, 1)]
        }

        /// The first walk: 1,860 files found so far, no final total, nothing per kind yet.
        static let counting = LookoutProgressDisplay(phase: .counting, done: 0, total: 1_860, totalIsFinal: false,
                                                     remaining: nil)

        /// Just started reading: the pace isn't steady yet, so no time left.
        static let readingEarly = LookoutProgressDisplay(
            phase: .reading, done: 96, total: 5_202, totalIsFinal: true, remaining: 5_106,
            kinds: [.image: KindProgress(done: 64, total: 2_310), .screenshot: KindProgress(done: 32, total: 640),
                    .pdf: KindProgress(done: 0, total: 1_402), .doc: KindProgress(done: 0, total: 850)])

        /// Mid-pass, with a pace and an estimate (1,992 files at 5.4 a second).
        static let readingMid = LookoutProgressDisplay(
            phase: .reading, done: 3_210, total: 5_202, totalIsFinal: true, remaining: 1_992,
            filesPerSecond: 5.4, estimatedRemaining: 369, kinds: kinds, skipped: 12, failed: 3,
            problems: someProblems)

        /// A big index, hours in.
        static let big = LookoutProgressDisplay(
            phase: .reading, done: 31_880, total: 48_213, totalIsFinal: true, remaining: 16_333,
            filesPerSecond: 3.1, estimatedRemaining: 5_268,
            kinds: [.image: KindProgress(done: 18_402, total: 24_110), .screenshot: KindProgress(done: 4_210, total: 4_300),
                    .pdf: KindProgress(done: 3_968, total: 11_803), .doc: KindProgress(done: 5_300, total: 8_000)],
            skipped: 41, failed: 7,
            problems: [problem(.tooSmall, 38), problem(.unreadable, 6), problem(.noText, 3),
                       problem(.passwordProtected, 1)])

        /// Low Power Mode holds the pass.
        static let pausedLowPower = LookoutProgressDisplay(
            phase: .paused(reason: .lowPowerMode), done: 3_210, total: 5_202, totalIsFinal: true, remaining: 1_992,
            kinds: kinds, skipped: 12, failed: 3, problems: someProblems)

        /// The person paused it.
        static let pausedByUser = LookoutProgressDisplay(
            phase: .paused(reason: .userPaused), done: 3_210, total: 5_202, totalIsFinal: true, remaining: 1_992,
            kinds: kinds)

        /// Everything else is read; a chosen folder is on a drive that isn't connected.
        static let waitingForDrive = LookoutProgressDisplay(
            phase: .waitingForDrive(name: "Backup Drive"), done: 4_980, total: 4_980, totalIsFinal: true,
            remaining: nil,
            kinds: [.image: KindProgress(done: 2_310, total: 2_310), .screenshot: KindProgress(done: 640, total: 640),
                    .pdf: KindProgress(done: 1_180, total: 1_180), .doc: KindProgress(done: 850, total: 850)])

        /// Done, this morning, with a few files skipped or unreadable.
        static func upToDate(now: Date = .now) -> LookoutProgressDisplay {
            let calendar = Calendar.current
            let finished = calendar.date(bySettingHour: 10, minute: 41, second: 0, of: now) ?? now
            return LookoutProgressDisplay(
                phase: .upToDate, done: 5_202, total: 5_202, totalIsFinal: true, remaining: 0, kinds: allRead,
                lastCompleted: finished, skipped: 12, failed: 3, problems: someProblems)
        }

        /// Reading stopped.
        static let failed = LookoutProgressDisplay(
            phase: .failed(message: LookoutFailure(kind: .indexing).message),
            done: 3_210, total: 5_202, totalIsFinal: true, remaining: 1_992, kinds: kinds, skipped: 12, failed: 3,
            problems: someProblems)

        /// Every sample by a stable name, for renders.
        static func all(now: Date = .now) -> [(name: String, display: LookoutProgressDisplay)] {
            [("counting", counting), ("reading-early", readingEarly), ("reading-mid", readingMid), ("big", big),
             ("paused-low-power", pausedLowPower), ("paused-user", pausedByUser),
             ("waiting-drive", waitingForDrive), ("up-to-date", upToDate(now: now)), ("failed", failed)]
        }
    }
}
