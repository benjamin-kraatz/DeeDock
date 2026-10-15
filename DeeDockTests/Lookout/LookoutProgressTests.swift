import Foundation
import Testing
@testable import DeeDock

/// Lookout's progress model: the smoothed pace and time left (`LookoutRateEstimator`), the phases, passes and the
/// first walk's growing total (`LookoutProgressTracker`), the problem counts the index service sends
/// (`LookoutProblemReason`), and how often the engine publishes it.
@MainActor struct LookoutProgressTests {
    private let start = Date(timeIntervalSince1970: 1_791_797_400)

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    // MARK: The pace

    @Test func thereIsNoPaceOrTimeLeftUntilEnoughHasBeenRead() {
        var pace = LookoutRateEstimator()
        pace.record(0, at: at(0))
        #expect(pace.unitsPerSecond == nil)
        pace.record(3, at: at(5))
        #expect(pace.unitsPerSecond == nil && pace.timeRemaining(for: 100) == nil)   // 5 s and 3 files: too early
        pace.record(4, at: at(12))
        #expect(pace.unitsPerSecond == nil)                                           // 12 s, but 4 files
        pace.record(12, at: at(12.5))
        #expect(abs((pace.unitsPerSecond ?? 0) - 12 / 12.5) < 0.0001)                 // the plain average so far
        #expect(pace.timeRemaining(for: 0) == nil)                                    // nothing left
        #expect(abs((pace.timeRemaining(for: 96) ?? 0) - 100) < 0.01)
    }

    @Test func aBurstOfFilesBarelyMovesTheSmoothedPace() throws {
        var pace = LookoutRateEstimator()
        var files = 0
        // Two files a second for a minute, sampled every second.
        for second in 0...60 {
            pace.record(files, at: at(Double(second)))
            files += 2
        }
        files -= 2
        #expect(abs(try #require(pace.unitsPerSecond) - 2) < 0.01)
        // Eight images committed at once, a tenth of a second later.
        files += 8
        pace.record(files, at: at(60.1))
        #expect(try #require(pace.unitsPerSecond) < 2.3)
        // Then one a second for three time constants: the pace follows down to about one.
        var time = 60.1
        for _ in 0..<Int(3 * LookoutRateEstimator.timeConstant) {
            time += 1
            files += 1
            pace.record(files, at: at(time))
        }
        let slowed = try #require(pace.unitsPerSecond)
        #expect(slowed > 1 && slowed < 1.15)
    }

    @Test func aPauseIsNotCountedAsSlowReading() throws {
        var pace = LookoutRateEstimator()
        for second in 0...30 { pace.record(second * 2, at: at(Double(second))) }
        let before = try #require(pace.unitsPerSecond)
        pace.pause()
        #expect(pace.unitsPerSecond == before)                 // a paused pass still has its pace
        // Ten minutes later, at the same count, reading goes on at the same speed.
        for second in 0...30 { pace.record(60 + second * 2, at: at(630 + Double(second))) }
        #expect(abs(try #require(pace.unitsPerSecond) - 2) < 0.01)
        #expect(pace.observedSeconds < 61)

        // Without the pause, the gap would have counted as ten minutes of reading nothing.
        var unpaused = LookoutRateEstimator()
        for second in 0...30 { unpaused.record(second * 2, at: at(Double(second))) }
        unpaused.record(60, at: at(630))
        #expect(try #require(unpaused.unitsPerSecond) < 1.5)
    }

    @Test func aCountThatStartsOverOrAClockThatGoesBackMovesNothing() throws {
        var pace = LookoutRateEstimator()
        for second in 0...20 { pace.record(second, at: at(Double(second))) }
        let before = try #require(pace.unitsPerSecond)
        pace.record(0, at: at(21))       // the service started a new run
        pace.record(5, at: at(20.5))     // and a clock went back
        #expect(pace.unitsPerSecond == before)
        pace.reset()
        #expect(pace.unitsPerSecond == nil && pace.observedUnits == 0)
    }

    // MARK: Phases

    private func index(_ activity: LookoutIndexStatus.Activity, pending: Int = 0, done: Int = 0, partial: Int = 0,
                       unfinished: Int = 0, discovered: Int? = nil, missing: [String] = [],
                       upToDateAt: Date? = nil) -> LookoutIndexStatus {
        var status = LookoutIndexStatus()
        status.activity = activity
        var states: [String: Int] = [:]
        if pending > 0 { states["pending"] = pending }
        if done > 0 { states["done"] = done }
        if partial > 0 { states["partial"] = partial }
        status.counts = IndexStore.Counts(byKindAndState: states.isEmpty ? [:] : ["image": states],
                                          unfinished: unfinished)
        status.discovered = discovered
        status.missingRoots = missing
        status.upToDateAt = upToDateAt
        return status
    }

    @Test func eachStatusHasItsPhase() {
        func phase(_ status: LookoutStatus, _ index: LookoutIndexStatus?) -> LookoutProgressDisplay.Phase? {
            var tracker = LookoutProgressTracker()
            return tracker.progress(status: status, index: index, now: start)?.phase
        }
        #expect(phase(.notSetUp, nil) == nil && phase(.off, index(.idle)) == nil)
        #expect(phase(.indexing(remaining: nil, progress: nil), nil) == .counting)
        #expect(phase(.indexing(remaining: 0, progress: nil), index(.syncing)) == .counting)
        #expect(phase(.indexing(remaining: 4, progress: 0.5), index(.indexing, pending: 4)) == .reading)
        #expect(phase(.indexing(remaining: 1, progress: 0.5), index(.finishingLongFiles, unfinished: 1)) == .reading)
        #expect(phase(.ready, index(.idle, done: 9)) == .upToDate)
        #expect(phase(.ready, index(.idle, done: 9, missing: ["/Volumes/Photos/2024"]))
            == .waitingForDrive(name: "Photos"))
        #expect(phase(.ready, index(.idle, missing: ["/Users/tester/Scans"])) == .waitingForDrive(name: "Scans"))
        #expect(phase(.paused(.lowPowerMode), index(.idle, pending: 3)) == .paused(reason: .lowPowerMode))
        #expect(phase(.paused(.warm), index(.idle, pending: 3)) == .paused(reason: .thermal))
        #expect(phase(.paused(.onBattery), index(.idle, pending: 3)) == .paused(reason: .onBattery))
        #expect(phase(.paused(.user), index(.paused, pending: 3)) == .paused(reason: .userPaused))
        // Settings has no card while the model downloads: the Files tab's card and chip show the download.
        #expect(phase(.waitingForModel, index(.waitingForModel, pending: 3)) == nil)
        let failure = LookoutFailure(kind: .service)
        #expect(phase(.failed(failure), nil) == .failed(message: failure.message))
    }

    @Test func theFirstWalksTotalGrowsUntilItIsCounted() throws {
        var tracker = LookoutProgressTracker()
        let counting = LookoutStatus.indexing(remaining: nil, progress: nil)
        let nothingYetProgress = tracker.progress(status: counting, index: index(.syncing), now: at(0))
        let nothingYet = try #require(nothingYetProgress)
        #expect(nothingYet.total == nil && !nothingYet.totalIsFinal && nothingYet.remaining == nil)
        for found in [250, 500, 750] {
            let walkingProgress = tracker.progress(status: counting, index: index(.syncing, discovered: found),
                                                   now: at(1))
            let walking = try #require(walkingProgress)
            #expect(walking.phase == .counting && walking.total == found && !walking.totalIsFinal)
            #expect(walking.done == 0 && walking.remaining == nil && walking.estimatedRemaining == nil)
        }
        // The walk is done: 800 files wait, and the total is final.
        let reading = LookoutStatus.indexing(remaining: 800, progress: 0)
        let countedProgress = tracker.progress(status: reading, index: index(.indexing, pending: 800), now: at(2))
        let counted = try #require(countedProgress)
        #expect(counted.phase == .reading && counted.total == 800 && counted.totalIsFinal && counted.remaining == 800)
        let partwayProgress = tracker.progress(status: reading, index: index(.indexing, pending: 500, done: 300),
                                               now: at(3))
        let partway = try #require(partwayProgress)
        #expect(partway.done == 300 && partway.total == 800 && partway.remaining == 500)
        #expect(partway.kinds[.image] == .init(done: 300, total: 800))
    }

    @Test func aLaterPassCountsOnlyItsOwnFilesAndAnUnfinishedFirstPassCountsFromTheStart() throws {
        let earlier = start.addingTimeInterval(-3_600)
        var later = LookoutProgressTracker()
        let readyProgress = later.progress(status: .ready, index: index(.idle, done: 10_000, upToDateAt: earlier),
                                           now: at(0))
        let ready = try #require(readyProgress)
        #expect(ready.phase == .upToDate && ready.done == 10_000 && ready.total == 10_000 && ready.remaining == 0)
        #expect(ready.lastCompleted == earlier)
        let reading = LookoutStatus.indexing(remaining: 3, progress: 0)
        let threeProgress = later.progress(status: reading,
                                           index: index(.indexing, pending: 3, done: 10_000, upToDateAt: earlier),
                                           now: at(1))
        let three = try #require(threeProgress)
        #expect(three.done == 0 && three.total == 3)
        let twoProgress = later.progress(status: reading,
                                         index: index(.indexing, pending: 1, done: 10_002, upToDateAt: earlier),
                                         now: at(2))
        let two = try #require(twoProgress)
        #expect(two.done == 2 && two.total == 3 && two.remaining == 1)
        // More files queued mid-pass make the total grow.
        let moreProgress = later.progress(status: reading,
                                          index: index(.indexing, pending: 5, done: 10_002, upToDateAt: earlier),
                                          now: at(3))
        let more = try #require(moreProgress)
        #expect(more.done == 2 && more.total == 7)

        // DOKK relaunched partway through the first pass: the index has never been up to date.
        var resumed = LookoutProgressTracker()
        let firstProgress = resumed.progress(status: reading, index: index(.indexing, pending: 6_000, done: 4_000),
                                             now: at(0))
        let first = try #require(firstProgress)
        #expect(first.done == 4_000 && first.total == 10_000 && first.remaining == 6_000 && first.lastCompleted == nil)
    }

    @Test func theTimeLeftComesWithAPaceGoesWhilePausedAndComesBack() throws {
        var tracker = LookoutProgressTracker()
        let reading = LookoutStatus.indexing(remaining: nil, progress: nil)
        var progress: LookoutProgressDisplay?
        // Two files a second for 20 s.
        for second in 0...20 {
            progress = tracker.progress(status: reading, index: index(.indexing, pending: 1_000 - 2 * second,
                                                                      done: 2 * second), now: at(Double(second)))
        }
        var running = try #require(progress)
        #expect(abs(try #require(running.filesPerSecond) - 2) < 0.01)
        #expect(abs(try #require(running.estimatedRemaining) - 480) < 1)    // 960 files at 2 a second
        // Low Power Mode: no pace or time while it waits.
        let pausedProgress = tracker.progress(status: .paused(.lowPowerMode),
                                              index: index(.idle, pending: 960, done: 40), now: at(25))
        let paused = try #require(pausedProgress)
        #expect(paused.filesPerSecond == nil && paused.estimatedRemaining == nil && paused.done == 40)
        // Resumed an hour later: the pace from before is back with the first file, not diluted by the wait.
        progress = tracker.progress(status: reading, index: index(.indexing, pending: 960, done: 40), now: at(3_625))
        progress = tracker.progress(status: reading, index: index(.indexing, pending: 958, done: 42), now: at(3_626))
        running = try #require(progress)
        #expect(abs(try #require(running.filesPerSecond) - 2) < 0.05)
        #expect(running.done == 42 && running.total == 1_000)
    }

    @Test func finishingLongFilesEstimatesByPagesNotFiles() throws {
        var tracker = LookoutProgressTracker()
        let reading = LookoutStatus.indexing(remaining: 2, progress: nil)
        var progress: LookoutProgressDisplay?
        for second in 0...20 {
            var status = index(.finishingLongFiles, done: 98, partial: 2, unfinished: 2)
            (status.done, status.total) = (10 * second, 600)
            progress = tracker.progress(status: reading, index: status, now: at(Double(second)))
        }
        let finishing = try #require(progress)
        #expect(finishing.phase == .reading && finishing.filesPerSecond == nil)
        #expect(abs(try #require(finishing.estimatedRemaining) - 40) < 0.5)   // 400 pages at 10 a second
        #expect(finishing.remaining == 2 && finishing.kinds[.image] == .init(done: 98, total: 100))
    }

    @Test func problemsArrivePerReasonMostFirst() throws {
        var status = index(.idle, done: 10)
        status.counts.byKindAndState["pdf"] = ["skipped": 3, "failed": 1]
        status.counts.problems = ["noText": 3, "unreadable": 1, "somethingNew": 4]
        var tracker = LookoutProgressTracker()
        let progressProgress = tracker.progress(status: .ready, index: status, now: start)
        let progress = try #require(progressProgress)
        #expect(progress.skipped == 3 && progress.failed == 1)
        // In the app's language, most first; a reason the app doesn't know is left out.
        #expect(progress.problems == [.init(reason: String(localized: .lookoutProblemNoText), count: 3),
                                      .init(reason: String(localized: .lookoutProblemUnreadable), count: 1)])
    }

    // MARK: Problems in the index

    @Test func theIndexCountsSkippedAndFailedFilesByReason() throws {
        let folder = LookoutTestFolder()
        let store = try IndexStore(directory: folder.url.appendingPathComponent("index"))
        let stored: [(String, String?)] = [
            ("skipped", "small image 120×90"), ("skipped", "small image 64×64"), ("skipped", "no text"),
            ("skipped", "no pages"), ("skipped", "in the cloud, not downloaded"), ("skipped", "excluded type"),
            ("skipped", "too large to read (900 MB)"), ("failed", "password-protected"),
            ("failed", "unreadable: Permission denied"), ("failed", "Error Domain=NSCocoaErrorDomain Code=259"),
            ("failed", nil), ("failed", "the model ran out of memory"), ("done", nil),
        ]
        for (number, (state, detail)) in stored.enumerated() {
            let id = try store.insert(Candidate(path: folder.path + "/f\(number).png", kind: .image, size: 1, mtime: 0,
                                                inode: UInt64(number + 1), device: 1))
            try store.finish(id, state: state, detail: detail)
        }
        let problems = try #require(try store.counts().problems)
        #expect(problems == ["tooSmall": 2, "noText": 2, "notDownloaded": 1, "excluded": 1, "tooLarge": 1,
                             "passwordProtected": 1, "unreadable": 3, "other": 1])
        // The SQL and the Swift rules agree.
        for (state, detail) in stored where state != "done" {
            #expect(problems[LookoutProblemReason.classify(state: state, detail: detail).rawValue] != nil)
        }
        #expect(LookoutProblemReason.classify(state: "failed", detail: nil) == .unreadable)
        #expect(LookoutProblemReason.classify(state: "skipped", detail: "the model ran out") == .other)
        #expect(LookoutProblemReason.allCases.allSatisfy { !String(localized: $0.title).isEmpty })
    }

    // MARK: Publishing

    @Test func theEngineChangesProgressAtMostTwiceASecondAndAlwaysShowsTheLatest() async {
        let connection = FakeIndexConnection()
        let engine = LookoutEngine(settings: .activeForTests, repository: nil, connection: connection,
                                   encoder: FakeQueryEncoder(), reader: FakeIndexReader(), monitor: FakeMonitor(),
                                   power: FakePowerPolicy(),
                                   paths: LookoutPaths(base: URL(fileURLWithPath: "/tmp/lookout-progress-tests",
                                                                 isDirectory: true)),
                                   canRun: true, progressInterval: .milliseconds(200))
        engine.start()
        connection.send(index(.indexing, pending: 100))
        #expect(engine.progress?.phase == .reading && engine.progress?.done == 0)
        // Files going by within the interval wait for it…
        connection.send(index(.indexing, pending: 99, done: 1))
        connection.send(index(.indexing, pending: 98, done: 2))
        #expect(engine.progress?.done == 0)
        // …and then the latest shows.
        #expect(await eventually { engine.progress?.done == 2 })
        // A new phase shows at once.
        connection.send(index(.idle, done: 100))
        #expect(engine.progress?.phase == .upToDate)
        engine.stop()
    }

    @Test func everyPreviewSampleIsConsistent() {
        for (name, sample) in LookoutProgressDisplay.Sample.all() {
            if let total = sample.total, sample.totalIsFinal { #expect(sample.done <= total, "\(name)") }
            if let remaining = sample.remaining, let total = sample.total, sample.totalIsFinal {
                #expect(sample.done + remaining == total, "\(name)")
            }
            #expect(sample.problems.map(\.count).reduce(0, +) == sample.skipped + sample.failed, "\(name)")
        }
        #expect(LookoutProgressDisplay.Sample.all().count == 9)
    }
}
