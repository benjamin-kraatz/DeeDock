import Foundation
import Observation

/// FIFO scheduling and local suppression. Dates are injected so scheduling has no UI dependency.
/// A missed calm opportunity advances to the next 69-second slot, never a catch-up burst.
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
    private var signals: [DiscoveryProposal.Signal: (count: Int, last: Date)] = [:]
    private(set) var queue: [String] = []
    private(set) var visible: DiscoveryProposal?
    private var sessionCount = 0
    private var nextSlot: Date?
    var enabled: Bool { saved.enabled && !unreadable }
    var needsClipboardSignal: Bool {
        enabled && catalog.contains { $0.signal == .clipboardChanged && !suppressed($0) }
    }

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
        queue.removeAll(); signals.removeAll(); visible = nil
        persist()
    }

    func record(_ signal: DiscoveryProposal.Signal, at now: Date) {
        guard enabled else { return }
        signals[signal] = (min((signals[signal]?.count ?? 0) + 1, 100), now)
        for proposal in catalog where proposal.signal == signal && !suppressed(proposal) {
            if signals[signal]!.count >= proposal.threshold,
               !queue.contains(proposal.id), visible?.id != proposal.id {
                queue.append(proposal.id)
            }
        }
    }

    /// Consumes at most one due slot. The caller must verify native gates before passing true.
    func advance(at now: Date, canPresent: Bool) -> DiscoveryProposal? {
        guard enabled, visible == nil, !queue.isEmpty else { return nil }
        queue.removeAll { id in catalog.first(where: { $0.id == id }).map(suppressed) ?? true }
        guard let id = queue.first, let proposal = catalog.first(where: { $0.id == id }) else { return nil }
        if let slot = nextSlot {
            guard now >= slot else { return nil }
            let missed = floor(now.timeIntervalSince(slot) / Self.spacing)
            nextSlot = slot.addingTimeInterval((missed + 1) * Self.spacing)
        }
        guard canPresent, sessionCount < 2,
              now >= saved.snoozed[id, default: .distantPast],
              let signal = signals[proposal.signal], now.timeIntervalSince(signal.last) >= proposal.calmInterval
        else { return nil }
        if !Calendar.current.isDate(saved.day, inSameDayAs: now) {
            saved.day = now; saved.dailyCount = 0
        }
        guard saved.dailyCount < 3 else { return nil }
        queue.removeFirst()
        visible = proposal
        sessionCount += 1; saved.dailyCount += 1
        saved.lastPresentation = now
        // Actual presentations anchor spacing, even when a timer is delivered late.
        nextSlot = now.addingTimeInterval(Self.spacing)
        persist()
        return proposal
    }

    func finish(forever: Bool, at now: Date) {
        guard let proposal = visible else { return }
        if forever { saved.dismissed.insert(proposal.id) }
        else { saved.snoozed[proposal.id] = now.addingTimeInterval(proposal.snoozeInterval) }
        visible = nil
        signals[proposal.signal] = nil
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
