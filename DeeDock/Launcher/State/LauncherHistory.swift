import Foundation
import Observation

/// App-wide successful DDock opens. No system-wide usage monitoring is involved.
@MainActor @Observable
final class LauncherHistory {
    struct Visit: Codable {
        let reference: ApplicationReference
        var lastOpened: Date
        var count: Int
    }
    private(set) var visits: [String: Visit] = [:]
    private(set) var unreadable = false
    @ObservationIgnored private let defaults: UserDefaults?
    private static let key = "launcher.history.v1"

    /// Nil persistence is useful for deterministic previews and leaves real preferences alone.
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.key) {
            do { visits = try JSONDecoder().decode([String: Visit].self, from: data) }
            catch { unreadable = true }
        }
    }

    func record(_ reference: ApplicationReference) {
        guard !unreadable else { return }
        visits[reference.id] = Visit(reference: reference, lastOpened: Date(), count: min(visits[reference.id]?.count ?? 0, 1_000_000) + 1)
        if visits.count > 500 {
            let keep = Set(visits.sorted { $0.value.lastOpened > $1.value.lastOpened }.prefix(500).map(\.key))
            visits = visits.filter { keep.contains($0.key) }
        }
        save()
    }

    /// Explicitly clearing history also replaces an unreadable history document.
    func clear() { visits = [:]; unreadable = false; defaults?.removeObject(forKey: Self.key) }

    private func save() {
        if let data = try? JSONEncoder().encode(visits) { defaults?.set(data, forKey: Self.key) }
    }
}
