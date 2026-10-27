import Foundation
import Observation

/// Shared, bounded badge history. AX sampling remains owned by DockBadgeController.
/// Current observations are ephemeral; a saved value is never presented as currently observed.
@MainActor @Observable
final class BadgeMemoryStore {
    private(set) var document = BadgeMemoryDocument()
    private(set) var current: [String: BadgeObservation] = [:]
    private(set) var requiresReset = false
    private(set) var storageFailed = false
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "dock.badge-memory.v1"
    private static let retention: TimeInterval = 7 * 86400

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func start() {
        if let stored = defaults.object(forKey: Self.key) {
            do {
                guard let data = stored as? Data, data.count <= 4_000_000 else { throw CocoaError(.coderReadCorrupt) }
                let decoded = try JSONDecoder().decode(BadgeMemoryDocument.self, from: data)
                guard decoded.version == 1, Self.valid(decoded) else { throw CocoaError(.coderReadCorrupt) }
                document = decoded
            } catch { requiresReset = true; storageFailed = true }
        }
        rekeyInstallations()
    }

    /// Replaces the live snapshot without appending a transition.
    ///
    /// Suspension passes an empty snapshot to stop presenting. A retained failure passes the
    /// hidden snapshot back. History stays as it was.
    func present(_ observations: [String: BadgeObservation]) {
        if current != observations { current = observations }
    }

    /// Called for actual snapshots, including unavailable scans. Identical samples do not persist.
    func observe(_ observations: [String: BadgeObservation], at date: Date = .now) {
        // Join a resolved scan onto the saved spelling before a missing key is stored as unknown.
        let observations = matchedObservations(observations)
        let previous = current
        if current != observations { current = observations }
        guard !requiresReset else { return }
        let before = document
        let paths = Set(document.apps.keys).union(observations.keys).union(previous.keys)
        for path in paths.sorted() {
            let value = observations[path] ?? .unknown
            if previous[path] != value {
                if var app = document.apps[path] {
                    if app.changes.last?.value != value {
                        app.changes.append(BadgeChange(value: value, date: date))
                        app.changes = Array(app.changes.suffix(20)); app.touched = date
                        document.apps[path] = app
                    }
                } else if let prior = previous[path], prior != .unknown,
                          (value.label != nil || prior.label != nil), document.apps.count < 100 {
                    // An untracked app's first sample only seeds live state. This also prevents
                    // a redundant first scan after relaunch from recreating deleted history.
                    document.apps[path] = BadgeAppMemory(changes: [BadgeChange(value: value, date: date)], touched: date)
                }
            }
        }
        prune(at: date)
        if document != before { persist() }
    }

    /// App activation does not call this. Only the explicit Mark checked control resets a baseline.
    func markChecked(_ path: String, at date: Date = .now) {
        guard !requiresReset, let value = current[path], value != .unknown else { return }
        if document.apps[path] == nil, document.apps.count >= 100 { return }
        var app = document.apps[path] ?? BadgeAppMemory(touched: date)
        app.checked = BadgeCheck(value: value, date: date); app.touched = date
        document.apps[path] = app
        persist()
    }

    func resetBaseline(_ path: String) {
        guard !requiresReset else { return }
        document.apps[path]?.checked = nil
        persist()
    }

    func clearApp(_ path: String) {
        guard !requiresReset else { return }
        document.apps[path] = nil
        persist()
    }

    /// Deletes all retained data.
    func clearAll() {
        document = BadgeMemoryDocument()
        requiresReset = false; storageFailed = false
        defaults.removeObject(forKey: Self.key)
    }

    /// Moves symlink and firmlink history onto the resolved path once.
    ///
    /// Case-only spellings keep the stored key, so a relaunch does not append `.unknown` for the
    /// old path or open a second row under a lowercased name. Live `current` values move with
    /// the records; they are not saved.
    private func rekeyInstallations() {
        guard !requiresReset else { return }
        let before = document
        document.apps = rekeyed(document.apps, merge: { mergeApps($0, $1) })
        if document != before { persist() }
        let remapped = matchedObservations(current)
        if remapped != current { current = remapped }
    }

    private func rekeyed<Value>(_ records: [String: Value], merge: (Value, Value) -> Value) -> [String: Value] {
        var groups: [String: [(String, Value)]] = [:]
        for (path, value) in records {
            groups[DockBadgePath.key(for: URL(fileURLWithPath: path)), default: []].append((path, value))
        }
        var result: [String: Value] = [:]
        for (identity, entries) in groups {
            let ordered = entries.sorted { $0.0 < $1.0 }
            let destination = DockBadgePath.preferredStorageKey(identity: identity, stored: ordered.map(\.0))
            let combined = ordered.dropFirst().reduce(ordered[0].1) { merge($0, $1.1) }
            result[destination] = result[destination].map { merge($0, combined) } ?? combined
        }
        return result
    }

    /// Keeps a checked baseline when two saved spellings collapse. Does not invent `.unknown`.
    private func mergeApps(_ first: BadgeAppMemory, _ second: BadgeAppMemory) -> BadgeAppMemory {
        let (primary, secondary) = first.checked == nil && second.checked != nil ? (second, first) : (first, second)
        var result = primary
        if result.checked == nil { result.checked = secondary.checked }
        if result.changes.isEmpty { result.changes = secondary.changes }
        if secondary.touched > result.touched { result.touched = secondary.touched }
        return result
    }

    /// Uses the stored spelling when a scan names the same installation.
    private func matchedObservations(_ observations: [String: BadgeObservation]) -> [String: BadgeObservation] {
        let stored = Array(document.apps.keys)
        var matched: [String: BadgeObservation] = [:]
        var conflicted: Set<String> = []
        for (path, value) in observations {
            let target = stored.first { DockBadgePath.sameInstallation($0, path) } ?? path
            if let existing = matched[target], existing != value { conflicted.insert(target) }
            matched[target] = value
        }
        for path in conflicted { matched[path] = .unknown }
        return matched
    }

    private func prune(at date: Date) {
        let cutoff = date.addingTimeInterval(-Self.retention)
        for path in document.apps.keys {
            document.apps[path]?.changes.removeAll { $0.date < cutoff }
            if let checked = document.apps[path]?.checked, checked.date < date.addingTimeInterval(-30 * 86400) {
                document.apps[path]?.checked = nil
            }
            if document.apps[path]?.changes.isEmpty == true, document.apps[path]?.checked == nil { document.apps[path] = nil }
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(document)
            // The writer must honor the same aggregate budget as the decoder. Keep the last
            // readable payload if unusually long paths/text exceed the encoded byte limit.
            guard data.count <= 4_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
            defaults.set(data, forKey: Self.key)
            storageFailed = false
        } catch { storageFailed = true }
    }

    private static func valid(_ doc: BadgeMemoryDocument) -> Bool {
        func valueValid(_ value: BadgeObservation) -> Bool {
            switch value {
            case .count(let count): return count >= 0
            case .text(let text): return text.count <= 128
            default: return true
            }
        }
        func dateValid(_ date: Date) -> Bool { date.timeIntervalSince1970.isFinite }
        func pathValid(_ path: String) -> Bool { path.hasPrefix("/") && path.count <= 4096 && path.hasSuffix(".app") }
        return doc.apps.count <= 100 && doc.apps.allSatisfy { path, app in
                pathValid(path) && dateValid(app.touched) && app.changes.count <= 20
                    && app.changes.allSatisfy { valueValid($0.value) && dateValid($0.date) }
                    && (app.checked.map { valueValid($0.value) && dateValid($0.date) } ?? true)
            }
    }
}
