import Foundation
import Observation

/// FIFO scheduling and local suppression. Dates are injected so scheduling has no UI dependency.
/// The 69-second slot moves only when a tip is presented, so a skipped tip cannot spend it and a late timer cannot release a burst.
@MainActor @Observable
final class DiscoveryEngine {
    static let spacing: TimeInterval = 69
    private let defaults: UserDefaults
    private let key = "discovery.state.v1"
    private let catalog: [DiscoveryProposal]
    private struct Saved: Codable {
        var enabled = true
        var dismissed: Set<String> = []
        var used: Set<String> = []
        var snoozed: [String: Date] = [:]
        var lastPresentation: Date?
        var day = Date.distantPast
        var dailyCount = 0
    }
    private var saved: Saved
    private var unreadable = false
    /// Signal progress per proposal: how often its signal arrived and when it last did. One signal
    /// can feed several proposals, such as the launch announcements. Showing a tip spends only its
    /// own progress, so the others queued on that signal stay eligible in this process.
    private var progress: [String: (count: Int, last: Date)] = [:]
    private(set) var queue: [String] = []
    private(set) var visible: DiscoveryProposal?
    private var sessionCount = 0
    private var nextSlot: Date?
    var enabled: Bool { saved.enabled && !unreadable }

    init(defaults: UserDefaults = .standard, catalog: [DiscoveryProposal]? = nil) {
        self.defaults = defaults
        self.catalog = catalog ?? DiscoveryProposal.catalog
        if let data = defaults.data(forKey: key) {
            if let decoded = try? JSONDecoder().decode(Saved.self, from: data) { saved = decoded }
            else { saved = Saved(); unreadable = true }
        } else { saved = Saved() }
        nextSlot = saved.lastPresentation?.addingTimeInterval(Self.spacing)
    }

    func setEnabled(_ enabled: Bool) {
        // Explicitly changing the switch repairs only Discovery's unreadable preferences.
        unreadable = false
        saved.enabled = enabled
        queue.removeAll(); progress.removeAll(); visible = nil
        persist()
    }

    func record(_ signal: DiscoveryProposal.Signal, at now: Date) {
        guard enabled else { return }
        for proposal in catalog where proposal.signal == signal && !suppressed(proposal) {
            let count = min((progress[proposal.id]?.count ?? 0) + 1, 100)
            progress[proposal.id] = (count, now)
            if count >= proposal.threshold,
               !queue.contains(proposal.id), visible?.id != proposal.id {
                queue.append(proposal.id)
            }
        }
    }

    /// Presents the first eligible queued tip. Spacing moves only when that presentation happens.
    /// The caller must verify native gates before passing true.
    func advance(at now: Date, canPresent: Bool) -> DiscoveryProposal? {
        guard enabled, visible == nil, !queue.isEmpty else { return nil }
        queue.removeAll { id in catalog.first(where: { $0.id == id }).map(suppressed) ?? true }
        guard canPresent, let index = dueIndex(at: now),
              let proposal = catalog.first(where: { $0.id == queue[index] }) else { return nil }
        if !Calendar.current.isDate(saved.day, inSameDayAs: now) {
            saved.day = now; saved.dailyCount = 0
        }
        queue.remove(at: index)
        visible = proposal
        sessionCount += 1; saved.dailyCount += 1
        saved.lastPresentation = now
        // Actual presentations anchor spacing, even when a timer is delivered late.
        nextSlot = now.addingTimeInterval(Self.spacing)
        persist()
        return proposal
    }

    /// Whether `advance(at: now, canPresent: true)` would present a tip. Changes nothing.
    ///
    /// The controller asks this before paying for its native gates (a window-server query and
    /// system idle time), which only matter when a tip is actually due.
    func isDue(at now: Date) -> Bool { dueIndex(at: now) != nil }

    /// Every gate `advance` applies apart from the caller's `canPresent`: enabled, nothing visible,
    /// the spacing slot reached, the session and daily caps, and an eligible queued tip. Shared by
    /// `advance` and `isDue` so the two cannot drift. Pure: a new day counts as zero shown without
    /// being written back.
    private func dueIndex(at now: Date) -> Int? {
        guard enabled, visible == nil else { return nil }
        if let slot = nextSlot, now < slot { return nil }
        guard sessionCount < 2 else { return nil }
        let dailyCount = Calendar.current.isDate(saved.day, inSameDayAs: now) ? saved.dailyCount : 0
        guard dailyCount < 3 else { return nil }
        return firstEligibleIndex(at: now)
    }

    /// First queue entry that is not suppressed, is past its snooze, and whose calm interval has
    /// elapsed. `advance` purges suppressed entries first; `isDue` relies on the check here.
    private func firstEligibleIndex(at now: Date) -> Int? {
        queue.firstIndex { id in
            guard let proposal = catalog.first(where: { $0.id == id }), !suppressed(proposal),
                  now >= saved.snoozed[id, default: .distantPast],
                  let progress = progress[id] else { return false }
            return now.timeIntervalSince(progress.last) >= proposal.calmInterval
        }
    }

    func finish(forever: Bool, at now: Date) {
        guard let proposal = visible else { return }
        if forever { saved.dismissed.insert(proposal.id) }
        else { saved.snoozed[proposal.id] = now.addingTimeInterval(proposal.snoozeInterval) }
        visible = nil
        // The shown tip has to qualify again from scratch; other tips keep their progress.
        progress[proposal.id] = nil
        persist()
    }

    /// All feature entry points report use, including use while Discovery is disabled.
    func markUsed(_ destination: DiscoveryProposal.Destination) {
        saved.used.insert(destination.rawValue)
        let ids = Set(catalog.filter { $0.destination == destination }.map(\.id))
        queue.removeAll { ids.contains($0) }
        if let visible, ids.contains(visible.id) { self.visible = nil }
        persist()
    }

    private func suppressed(_ proposal: DiscoveryProposal) -> Bool {
        saved.dismissed.contains(proposal.id) || saved.used.contains(proposal.destination.rawValue)
    }

    private func persist() {
        guard !unreadable, let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: key)
    }
}
