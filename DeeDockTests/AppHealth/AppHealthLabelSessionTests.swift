import Foundation
import Testing
@testable import DeeDock

/// One question's phases, timers, and results. Timers run 1000× faster than real time: a second is a millisecond.
@MainActor
struct AppHealthLabelSessionTests {
    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_793_000_000)
    }

    private final class Recorder {
        var results: [AppHealthLabelSession.Result] = []
        var finished = 0
        var commands: [AppHealthLabelSession.MenuCommand] = []
    }

    private func makeSession(source: AppHealthLabelSource = .prompt, clock: Clock? = nil,
                             fast: Bool = true) -> (AppHealthLabelSession, Recorder) {
        let clock = clock ?? Clock()
        let session = AppHealthLabelSession(
            app: AppHealthAppDisplay(bundleID: "com.example.App", name: "App", icon: nil), reason: "Busy",
            source: source, timing: source == .prompt ? .prompt : .manual, now: { clock.date },
            sleep: { duration in try await Task.sleep(for: fast ? duration / 1000 : .seconds(3600)) })
        let recorder = Recorder()
        session.labelled = { recorder.results.append($0) }
        session.finished = { recorder.finished += 1 }
        session.menuCommand = { recorder.commands.append($0) }
        return (session, recorder)
    }

    @Test("An unanswered prompt expires as noAnswer, neither dismissed nor interrupted")
    func expiry() async {
        let (session, recorder) = makeSession()
        session.start()
        #expect(await labellingEventually { recorder.finished == 1 })
        #expect(recorder.results == [AppHealthLabelSession.Result(answer: .noAnswer, answeredAt: Date(timeIntervalSince1970: 1_793_000_000))])
    }

    @Test("The pointer over the prompt pauses the expiry and keeps the time left")
    func engagementPauses() async throws {
        let clock = Clock()
        let (session, recorder) = makeSession(clock: clock)
        session.start()
        #expect(session.expiry == .init(fraction: 1, secondsLeft: 60))
        clock.date += 15
        session.setEngaged(true)
        #expect(session.expiry == .init(fraction: 0.75, secondsLeft: nil))
        try await Task.sleep(for: .milliseconds(150))
        #expect(recorder.results.isEmpty)

        session.setEngaged(false)
        #expect(session.expiry == .init(fraction: 0.75, secondsLeft: 45))
        #expect(await labellingEventually { recorder.finished == 1 })
        #expect(recorder.results.first?.answer == .noAnswer)
    }

    @Test("Expected writes once, thanks, then finishes")
    func expected() async {
        let (session, recorder) = makeSession()
        session.start()
        session.answer(.expected)
        #expect(session.phase == .thanks)
        #expect(recorder.results.map(\.answer) == [.expected])
        session.answer(.notSure)
        #expect(recorder.results.count == 1)
        #expect(await labellingEventually { recorder.finished == 1 })
    }

    @Test("Misbehaving asks the follow-up; a detail is written with the time of the first answer")
    func followUpDetail() async {
        let clock = Clock()
        let (session, recorder) = makeSession(clock: clock)
        session.start()
        clock.date += 4
        session.answer(.misbehaving)
        #expect(session.phase == .followUp)
        #expect(session.expiry == nil)
        #expect(recorder.results.isEmpty)
        clock.date += 3
        session.chooseDetail(.memoryGrowing)
        #expect(recorder.results == [AppHealthLabelSession.Result(answer: .misbehaving, detail: .memoryGrowing,
                                                                  answeredAt: Date(timeIntervalSince1970: 1_793_000_004))])
        #expect(session.phase == .thanks)
    }

    @Test("An ignored follow-up writes Misbehaving without a detail")
    func followUpTimeout() async {
        let (session, recorder) = makeSession()
        session.start()
        session.answer(.misbehaving)
        #expect(await labellingEventually { recorder.finished == 1 })
        #expect(recorder.results.map(\.answer) == [.misbehaving])
        #expect(recorder.results.first?.detail == nil)
        #expect(recorder.results.first?.dismissed == false)
    }

    @Test("Closing: noAnswer and dismissed while asking, Misbehaving after the first answer")
    func dismiss() {
        let (asking, askingRecorder) = makeSession(fast: false)
        asking.start()
        asking.dismiss()
        #expect(askingRecorder.results.map(\.answer) == [.noAnswer])
        #expect(askingRecorder.results.first?.dismissed == true)
        #expect(askingRecorder.finished == 1)

        let (followUp, followUpRecorder) = makeSession(fast: false)
        followUp.answer(.misbehaving)
        followUp.dismiss()
        #expect(followUpRecorder.results.map(\.answer) == [.misbehaving])
        #expect(followUpRecorder.results.first?.dismissed == false)
    }

    @Test("Interruption writes what is known, marked interrupted, and nothing after a label")
    func interrupt() {
        let (asking, askingRecorder) = makeSession(fast: false)
        asking.start()
        asking.interrupt()
        #expect(askingRecorder.results.first?.answer == .noAnswer)
        #expect(askingRecorder.results.first?.interrupted == true)
        #expect(askingRecorder.finished == 1)

        let (thanks, thanksRecorder) = makeSession(fast: false)
        thanks.answer(.notSure)
        thanks.interrupt()
        #expect(thanksRecorder.results.map(\.answer) == [.notSure])
        #expect(thanksRecorder.results.first?.interrupted == false)
        #expect(thanksRecorder.finished == 1)
    }

    @Test("A menu command ends the question as dismissed before it runs")
    func menuCommand() {
        let (session, recorder) = makeSession(fast: false)
        session.perform(.dontAsk)
        #expect(recorder.results.first?.dismissed == true)
        #expect(recorder.finished == 1)
        #expect(recorder.commands == [.dontAsk])
    }

    @Test("Manual questions never expire")
    func manualNeverExpires() async throws {
        let (session, recorder) = makeSession(source: .manual)
        session.start()
        #expect(session.expiry == nil)
        try await Task.sleep(for: .milliseconds(150))
        #expect(recorder.results.isEmpty)
    }

    @Test("The keyboard moves through the current controls, wrapping, and activates the highlighted one")
    func keyboard() {
        let (session, recorder) = makeSession(fast: false)
        #expect(session.highlighted == nil)
        session.setKeyboardActive(true)
        #expect(session.highlighted == .answer(.expected))
        session.moveHighlight(by: 1)
        #expect(session.highlighted == .answer(.misbehaving))
        session.activateHighlighted()
        #expect(session.phase == .followUp)
        #expect(session.highlighted == .detail(.spinning))
        session.moveHighlight(by: -1)
        #expect(session.highlighted == .skip)
        session.activateHighlighted()
        #expect(recorder.results.map(\.answer) == [.misbehaving])
        #expect(recorder.results.first?.detail == nil)
        #expect(session.highlighted == nil)
    }
}

@MainActor
func labellingEventually(timeout: Duration = .seconds(3), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}
