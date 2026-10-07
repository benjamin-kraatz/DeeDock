import AppKit
import Foundation
import Observation

/// The rule that decides whether a badge is news.
///
/// A count is new while it is higher than the count last acknowledged. Any other label is new
/// while it differs from the acknowledged one. A badge nobody acknowledged is new.
nonisolated enum BadgeAttention {
    static func isNew(label: String?, acknowledged: String?) -> Bool {
        guard let label else { return false }
        guard let acknowledged else { return true }
        if case .count(let current) = BadgeObservation(label: label),
           case .count(let previous) = BadgeObservation(label: acknowledged) {
            return current > previous
        }
        return label != acknowledged
    }
}

/// Which app badges are news, for the Line icon ring and its tooltip.
///
/// Clicking a tile or bringing its app to the front acknowledges the badge it shows. A badge that
/// arrives while its app is frontmost is acknowledged straight away, because the person is
/// already looking at it. A scan that sees a badge cleared forgets its acknowledgement, so the
/// next badge from that app is new. A count that drops lowers the acknowledgement with it, so a
/// later rise is new again.
///
/// Acknowledgements persist, so a badge someone has already dealt with stays quiet after a
/// relaunch. They are separate from Badge Memory's checked baseline, which only **Mark checked**
/// moves.
@MainActor @Observable
final class BadgeAttentionStore {
    nonisolated struct Acknowledgement: Codable, Equatable {
        var label: String
        /// When the badge was acknowledged. Notification banners older than this are not news.
        var date: Date
    }

    private(set) var acknowledged: [String: Acknowledgement] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "dock.badge-attention.v1"
    /// Bounds the saved record; the oldest acknowledgements go first.
    private static let capacity = 200

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: Acknowledgement].self, from: data) {
            acknowledged = decoded
        }
    }

    /// Whether the badge `label` on the app at `key` is news. `key` comes from ``DockBadgePath/key(for:)``.
    func isNew(key: String, label: String?) -> Bool {
        BadgeAttention.isNew(label: label, acknowledged: acknowledged[key]?.label)
    }

    /// When the badge at `key` was last acknowledged, or nil if it never was.
    func acknowledgedDate(key: String) -> Date? { acknowledged[key]?.date }

    /// Records that the person has seen `label`. Does nothing for a missing or already quiet badge.
    /// - Parameter route: How it was seen, counted for `usage_summary`.
    func acknowledge(key: String, label: String?, via route: AnalyticsBadgeAcknowledgement, at date: Date = .now) {
        guard let label, isNew(key: key, label: label) else { return }
        acknowledged[key] = Acknowledgement(label: label, date: date)
        persist()
        Analytics.count(.badgeAcknowledged(route))
    }

    /// Applies one completed badge scan.
    ///
    /// Call it only with real observations. A paused or sleeping reader presents no badges, and
    /// treating that as "cleared" would make every standing badge new again on wake.
    /// - Parameter frontmost: The badge key of the frontmost application, if any.
    func reconcile(_ snapshot: [String: BadgeObservation], frontmost: String?, at date: Date = .now) {
        var next = acknowledged
        for (key, acknowledgement) in acknowledged {
            switch snapshot[key] {
            case .cleared:
                next[key] = nil
            case .count(let current):
                if case .count(let previous) = BadgeObservation(label: acknowledgement.label), current < previous {
                    next[key]?.label = String(current)
                }
            default:
                break
            }
        }
        if let frontmost, let label = snapshot[frontmost]?.label,
           BadgeAttention.isNew(label: label, acknowledged: next[frontmost]?.label) {
            next[frontmost] = Acknowledgement(label: label, date: date)
            Analytics.count(.badgeAcknowledged(.frontmost))
        }
        guard next != acknowledged else { return }
        acknowledged = next
        persist()
    }

    private func persist() {
        if acknowledged.count > Self.capacity {
            let overflow = acknowledged.sorted { $0.value.date < $1.value.date }.prefix(acknowledged.count - Self.capacity)
            for (key, _) in overflow { acknowledged[key] = nil }
        }
        guard let data = try? JSONEncoder().encode(acknowledged) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
