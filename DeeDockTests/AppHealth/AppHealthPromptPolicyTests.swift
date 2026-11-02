import Foundation
import Testing
@testable import DeeDock

/// Prompt caps, the "Don't ask" list, the pause, the ordinary share and draw, and the persisted history.
struct AppHealthPromptPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    private func context(at date: Date? = nil, visible: Bool = false, pausedUntil: Date? = nil,
                         dontAsk: Set<String> = [], own: String? = "dev.dokk.app") -> AppHealthPromptPolicy.Context {
        AppHealthPromptPolicy.Context(now: date ?? now, questionVisible: visible, pausedUntil: pausedUntil,
                                      dontAsk: dontAsk, ownBundleID: own)
    }

    private func candidate(_ app: String, _ trigger: AppHealthPromptTrigger, reasons: [AppHealthPromptReason] = [],
                           cpu: Double = 90) -> AppHealthPromptCandidate {
        AppHealthPromptCandidate(app: app, kind: .regular, trigger: trigger,
                                 reasons: trigger == .rule && reasons.isEmpty ? [.cpu, .background] : reasons,
                                 evidence: AppHealthSuspicionEvidence(meanCPUPercent: cpu))
    }

    @Test("At most 8 prompts in a rolling hour")
    func hourlyCap() {
        let seven = AppHealthPromptHistory(shownAt: (1...7).map { now.addingTimeInterval(-Double($0) * 60) })
        #expect(AppHealthPromptPolicy.allowsAnyPrompt(history: seven, context: context()))

        var eight = seven
        eight.shownAt.append(now.addingTimeInterval(-3599))
        #expect(!AppHealthPromptPolicy.allowsAnyPrompt(history: eight, context: context()))
        // An hour after the oldest, it no longer counts.
        #expect(AppHealthPromptPolicy.allowsAnyPrompt(history: eight, context: context(at: now.addingTimeInterval(1))))
        #expect(AppHealthPromptPolicy.choose(from: [candidate("a", .rule)], history: eight, context: context(),
                                             draw: { 0 }) == nil)
    }

    @Test("Recording prunes prompts outside the rolling hour")
    func recordPrunes() {
        var history = AppHealthPromptHistory(shownAt: [now.addingTimeInterval(-3600), now.addingTimeInterval(-10)],
                                             lastShown: ["old": now.addingTimeInterval(-1200)])
        history.record(app: "a", trigger: .rule, at: now)
        #expect(history.shownAt == [now.addingTimeInterval(-10), now])
        #expect(history.lastShown == ["a": now])
        #expect(history.triggers == [.rule])
    }

    @Test("At most one prompt per app per 20 minutes")
    func perAppInterval() {
        let recent = AppHealthPromptHistory(lastShown: ["a": now.addingTimeInterval(-19 * 60)])
        #expect(!AppHealthPromptPolicy.allowsAsking(about: "a", history: recent, context: context()))
        #expect(AppHealthPromptPolicy.allowsAsking(about: "b", history: recent, context: context()))
        let old = AppHealthPromptHistory(lastShown: ["a": now.addingTimeInterval(-20 * 60)])
        #expect(AppHealthPromptPolicy.allowsAsking(about: "a", history: old, context: context()))

        // The capped app is skipped; another suspicious app is asked about instead.
        let choice = AppHealthPromptPolicy.choose(from: [candidate("a", .rule, cpu: 300), candidate("b", .rule)],
                                                  history: recent, context: context(), draw: { 0 })
        #expect(choice?.app == "b")
    }

    @Test("Never DOKK itself, never an app on the Don't ask list")
    func excludedApps() {
        let history = AppHealthPromptHistory()
        let ctx = context(dontAsk: ["com.example.Quiet"])
        #expect(!AppHealthPromptPolicy.allowsAsking(about: "dev.dokk.app", history: history, context: ctx))
        #expect(!AppHealthPromptPolicy.allowsAsking(about: "com.example.Quiet", history: history, context: ctx))
        let choice = AppHealthPromptPolicy.choose(
            from: [candidate("dev.dokk.app", .rule), candidate("com.example.Quiet", .rule)],
            history: history, context: ctx, draw: { 0 })
        #expect(choice == nil)
    }

    @Test("One question at a time")
    func oneVisible() {
        #expect(!AppHealthPromptPolicy.allowsAnyPrompt(history: .init(), context: context(visible: true)))
    }

    @Test("Pause labelling for today lasts until the next local midnight, across the day boundary")
    @MainActor
    func pauseUntilMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let lateEvening = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 23, minute: 30)))
        let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3)))
        let preferences = AppHealthLabellingPreferences(defaults: nil, calendar: calendar, now: { lateEvening })
        preferences.pauseForToday()
        #expect(preferences.pausedUntil == midnight)

        let history = AppHealthPromptHistory()
        let beforeMidnight = context(at: midnight.addingTimeInterval(-1), pausedUntil: preferences.pausedUntil)
        #expect(!AppHealthPromptPolicy.allowsAnyPrompt(history: history, context: beforeMidnight))
        let atMidnight = context(at: midnight, pausedUntil: preferences.pausedUntil)
        #expect(AppHealthPromptPolicy.allowsAnyPrompt(history: history, context: atMidnight))
        #expect(preferences.isPaused(at: midnight.addingTimeInterval(-1)))
        #expect(!preferences.isPaused(at: midnight))
    }

    @Test("Manual labels leave the caps untouched")
    func manualBypass() {
        var history = AppHealthPromptHistory()
        for minute in 0..<12 {
            history.record(app: "a", trigger: .manual, at: now.addingTimeInterval(Double(minute) * 60))
        }
        #expect(history == AppHealthPromptHistory())
    }

    @Test("Ordinary prompts stay under a quarter of the remembered ones")
    func ordinaryShare() {
        #expect(AppHealthPromptPolicy.ordinaryShareAllows([]))
        #expect(AppHealthPromptPolicy.ordinaryShareAllows([.rule, .rule, .rule]))
        // 1 < 0.25 × 5
        #expect(AppHealthPromptPolicy.ordinaryShareAllows([.rule, .rule, .rule, .ordinary]))
        // 1 < 0.25 × 4 fails
        #expect(!AppHealthPromptPolicy.ordinaryShareAllows([.rule, .rule, .ordinary]))
        // Only the last 100 count: 100 rules push the early ordinary prompts out.
        let early = Array(repeating: AppHealthPromptTrigger.ordinary, count: 30)
        #expect(AppHealthPromptPolicy.ordinaryShareAllows(early + Array(repeating: .rule, count: 100)))
    }

    @Test("An eligible ordinary candidate is asked about with probability 1/3")
    func ordinaryDraw() {
        let history = AppHealthPromptHistory(triggers: [.rule, .rule, .rule])
        let busy = [candidate("a", .ordinary, cpu: 50), candidate("b", .ordinary, cpu: 70)]
        var draws = 0
        let picked = AppHealthPromptPolicy.choose(from: busy, history: history, context: context()) {
            draws += 1
            return 0.33
        }
        #expect(picked?.app == "b")
        #expect(draws == 1)
        let skipped = AppHealthPromptPolicy.choose(from: busy, history: history, context: context(), draw: { 1.0 / 3 })
        #expect(skipped == nil)

        // Over the share, no draw happens at all.
        var gatedDraws = 0
        let gated = AppHealthPromptPolicy.choose(from: busy, history: AppHealthPromptHistory(triggers: [.ordinary]),
                                                 context: context()) {
            gatedDraws += 1
            return 0
        }
        #expect(gated == nil)
        #expect(gatedDraws == 0)
    }

    @Test("A suspicious candidate always wins over an ordinary one, without a draw")
    func suspiciousWins() {
        var draws = 0
        let choice = AppHealthPromptPolicy.choose(
            from: [candidate("busy", .ordinary, cpu: 300), candidate("spin", .rule, cpu: 85)],
            history: .init(), context: context()) {
            draws += 1
            return 0
        }
        #expect(choice?.app == "spin")
        #expect(draws == 0)
    }

    @Test("Among suspicious apps, more flags win, then more CPU")
    func suspiciousOrder() {
        let choice = AppHealthPromptPolicy.choose(
            from: [candidate("cpu", .rule, reasons: [.cpu, .background], cpu: 400),
                   candidate("many", .rule, reasons: [.cpu, .background, .memory], cpu: 90)],
            history: .init(), context: context(), draw: { 0 })
        #expect(choice?.app == "many")
    }

    @Test("Prompts dated after now, from a clock set back, do not silence prompts")
    func clockSetBack() {
        let future = AppHealthPromptHistory(shownAt: Array(repeating: now.addingTimeInterval(600), count: 8),
                                            lastShown: ["a": now.addingTimeInterval(600)])
        #expect(AppHealthPromptPolicy.allowsAnyPrompt(history: future, context: context()))
        #expect(AppHealthPromptPolicy.allowsAsking(about: "a", history: future, context: context()))
    }

    @Test("The prompt history persists next to the Don't ask list without losing it")
    @MainActor
    func persistence() throws {
        let suite = "AppHealthPromptPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppHealthLabellingPreferences(defaults: defaults, now: { self.now })
        first.addDontAsk("com.example.Quiet")
        first.recordPrompt(app: "com.example.Busy", trigger: .ordinary, at: now)

        let second = AppHealthLabellingPreferences(defaults: defaults, now: { self.now })
        #expect(second.dontAsk == ["com.example.Quiet"])
        #expect(second.promptHistory.triggers == [.ordinary])
        #expect(second.promptHistory.lastShown["com.example.Busy"] == now)
    }
}
