import Foundation

/// What the prompt policy remembers about prompts it already showed, persisted with the labelling preferences
/// under `appHealth.prompts.v1` (key `promptHistory`) so the caps survive a relaunch.
///
/// Only automatic prompts are recorded; manual labels bypass every cap and leave no trace here. Entries that can
/// no longer affect a decision are pruned on every record, so the stored object stays small.
nonisolated struct AppHealthPromptHistory: Codable, Equatable, Sendable {
    /// When each prompt of the last rolling hour appeared, oldest first.
    var shownAt: [Date] = []
    /// When each app was last asked about, kept for the per-app interval only.
    var lastShown: [String: Date] = [:]
    /// Triggers of the last `AppHealthPromptPolicy.rememberedTriggers` shown prompts, oldest first, for the
    /// ordinary share.
    var triggers: [AppHealthPromptTrigger] = []

    init(shownAt: [Date] = [], lastShown: [String: Date] = [:], triggers: [AppHealthPromptTrigger] = []) {
        self.shownAt = shownAt
        self.lastShown = lastShown
        self.triggers = triggers
    }

    private enum CodingKeys: String, CodingKey {
        case shownAt, lastShown, triggers
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shownAt = try container.decodeIfPresent([Date].self, forKey: .shownAt) ?? []
        lastShown = try container.decodeIfPresent([String: Date].self, forKey: .lastShown) ?? [:]
        // A trigger this build does not know would fail the whole array; drop the history of shares instead.
        triggers = (try? container.decodeIfPresent([AppHealthPromptTrigger].self, forKey: .triggers)) ?? []
    }

    /// Notes a shown automatic prompt and prunes what no longer matters at `date`.
    mutating func record(app: String, trigger: AppHealthPromptTrigger, at date: Date) {
        guard trigger != .manual else { return }
        shownAt.append(date)
        lastShown[app] = date
        triggers.append(trigger)
        prune(at: date)
    }

    /// Drops prompts outside the rolling hour, per-app entries past the per-app interval, and triggers beyond the
    /// remembered count. Entries dated after `date` are dropped too: the clock was set back, and keeping them would
    /// silence prompts until the clock caught up.
    mutating func prune(at date: Date) {
        shownAt.removeAll { !AppHealthPromptPolicy.isWithin(AppHealthPromptPolicy.rollingWindow, of: date, $0) }
        lastShown = lastShown.filter { AppHealthPromptPolicy.isWithin(AppHealthPromptPolicy.perAppInterval, of: date, $0.value) }
        if triggers.count > AppHealthPromptPolicy.rememberedTriggers {
            triggers.removeFirst(triggers.count - AppHealthPromptPolicy.rememberedTriggers)
        }
    }
}
