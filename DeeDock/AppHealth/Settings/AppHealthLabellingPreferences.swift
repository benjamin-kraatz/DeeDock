import Foundation
import Observation

/// The person's choices that silence labelling prompts, persisted as JSON under `appHealth.prompts.v1`.
///
/// Holds the "Don't ask about this app" list and "Pause labelling for today", which Settings shows and can undo,
/// and the prompt policy's memory of shown prompts (`promptHistory`), which only the labelling coordinator uses.
/// Saving merges into the stored object, so fields a newer build added are kept.
///
/// Change these through `AppHealthController` (`dontAsk(about:)`, `allowAsking(about:)`,
/// `pauseLabellingForToday()`, `resumeLabelling()`), which also writes the matching events.
@MainActor @Observable
final class AppHealthLabellingPreferences {
    /// The stored document.
    nonisolated struct Document: Codable, Equatable, Sendable {
        /// Bundle identifiers the person asked never to be asked about.
        var dontAsk: Set<String> = []
        /// Prompts stay silent until this moment: the next local midnight after "Pause labelling for today".
        var pausedUntil: Date?
        /// Shown automatic prompts, for the rate caps and the ordinary share.
        var promptHistory = AppHealthPromptHistory()

        init(dontAsk: Set<String> = [], pausedUntil: Date? = nil, promptHistory: AppHealthPromptHistory = .init()) {
            self.dontAsk = dontAsk
            self.pausedUntil = pausedUntil
            self.promptHistory = promptHistory
        }

        private enum CodingKeys: String, CodingKey {
            case dontAsk, pausedUntil, promptHistory
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            dontAsk = try container.decodeIfPresent(Set<String>.self, forKey: .dontAsk) ?? []
            pausedUntil = try container.decodeIfPresent(Date.self, forKey: .pausedUntil)
            // A damaged history only loosens the caps for an hour; it must not cost the "Don't ask" list.
            promptHistory = (try? container.decodeIfPresent(AppHealthPromptHistory.self, forKey: .promptHistory)) ?? .init()
        }
    }

    static let defaultsKey = "appHealth.prompts.v1"

    private(set) var dontAsk: Set<String>
    private(set) var pausedUntil: Date?
    /// Shown automatic prompts. Not observed: no view reads it, and it changes with every prompt.
    @ObservationIgnored private(set) var promptHistory: AppHealthPromptHistory
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    /// - Parameters:
    ///   - defaults: Nil for an in-memory store, as previews and tests use.
    ///   - calendar: Decides where "today" ends.
    init(defaults: UserDefaults?, initial: Document = Document(), calendar: Calendar = .current,
         now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        let document = defaults?.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(Document.self, from: $0) } ?? initial
        dontAsk = document.dontAsk
        pausedUntil = document.pausedUntil
        promptHistory = document.promptHistory
        if let pausedUntil, pausedUntil <= now() { self.pausedUntil = nil }
    }

    /// Whether prompts are paused at `date`.
    func isPaused(at date: Date) -> Bool {
        pausedUntil.map { date < $0 } ?? false
    }

    /// Whether prompts are paused now.
    var isPaused: Bool { isPaused(at: now()) }

    /// Adds `app` to the "Don't ask" list. Returns false when it was already there.
    @discardableResult
    func addDontAsk(_ app: String) -> Bool {
        guard dontAsk.insert(app).inserted else { return false }
        save()
        return true
    }

    /// Removes `app` from the "Don't ask" list. Returns false when it was not there.
    @discardableResult
    func removeDontAsk(_ app: String) -> Bool {
        guard dontAsk.remove(app) != nil else { return false }
        save()
        return true
    }

    /// Pauses prompts until the next local midnight.
    func pauseForToday() {
        let current = now()
        pausedUntil = calendar.nextDate(after: current, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                        matchingPolicy: .nextTime)
            ?? current.addingTimeInterval(24 * 60 * 60)
        save()
    }

    /// Notes an automatic prompt that just appeared, for the caps and the ordinary share.
    func recordPrompt(app: String, trigger: AppHealthPromptTrigger, at date: Date) {
        promptHistory.record(app: app, trigger: trigger, at: date)
        save()
    }

    /// Ends a pause early. Returns false when nothing was paused.
    @discardableResult
    func resume() -> Bool {
        guard pausedUntil != nil else { return false }
        pausedUntil = nil
        save()
        return true
    }

    private func save() {
        guard let defaults else { return }
        // Merge into the stored object so fields a newer build added are kept.
        var object = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let document = Document(dontAsk: dontAsk, pausedUntil: pausedUntil, promptHistory: promptHistory)
        guard let data = try? JSONEncoder().encode(document),
              let own = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        object["dontAsk"] = own["dontAsk"]
        object["pausedUntil"] = own["pausedUntil"]
        object["promptHistory"] = own["promptHistory"]
        guard let merged = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        defaults.set(merged, forKey: Self.defaultsKey)
    }
}
