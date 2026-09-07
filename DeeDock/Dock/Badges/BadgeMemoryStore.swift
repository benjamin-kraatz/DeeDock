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
    @ObservationIgnored private var session: FocusSession?
    private static let key = "dock.badge-memory.v1"
    private static let retention: TimeInterval = 7 * 86400

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func start(session: FocusSession?, at date: Date = .now) {
        if let stored = defaults.object(forKey: Self.key) {
            do {
                guard let data = stored as? Data, data.count <= 4_000_000 else { throw CocoaError(.coderReadCorrupt) }
                let decoded = try JSONDecoder().decode(BadgeMemoryDocument.self, from: data)
                guard decoded.version == 1, Self.valid(decoded) else { throw CocoaError(.coderReadCorrupt) }
                document = decoded
            } catch { requiresReset = true; storageFailed = true }
        }
        if document.active != nil { document.active?.incomplete = true }
        synchronize(session: session, at: date, allowStart: false)
    }

    /// Called for actual snapshots, including unavailable scans. Identical samples do not persist.
    func observe(_ observations: [String: BadgeObservation], session: FocusSession?, at date: Date = .now) {
        synchronize(session: session, at: date)
        let previous = current
        current = observations
        guard !requiresReset else { return }
        let before = document
        let paths = Set(document.apps.keys).union(observations.keys).union(document.active?.rows.keys.map { $0 } ?? [])
        for path in paths.sorted() {
            let value = observations[path] ?? .unknown
            if previous[path] != value {
                if var app = document.apps[path] {
                    if app.changes.last?.value != value {
                        app.changes.append(BadgeChange(value: value, date: date))
                        app.changes = Array(app.changes.suffix(20)); app.touched = date
                        document.apps[path] = app
                    }
                } else if value.label != nil, document.apps.count < 100 {
                    document.apps[path] = BadgeAppMemory(changes: [BadgeChange(value: value, date: date)], touched: date)
                }
            }
            collect(path: path, value: value)
        }
        prune(at: date)
        if document != before { persist() }
    }

    /// A session's deadline is checked before accepting a sample, even if its timer task is delayed.
    func synchronize(session: FocusSession?, at date: Date = .now, allowStart: Bool = true) {
        self.session = session
        guard !requiresReset else { return }
        let before = document
        if let active = document.active,
           session?.id != active.id || session?.phase == .completed ||
            (session?.phase == .running && session!.remaining(at: date) <= 0) {
            var ended = active
            ended.ended = min(date, session?.id == active.id ? session?.deadline ?? date : date)
            document.digests.insert(ended, at: 0)
            document.active = nil
        }
        if let session, document.lastSessionID != session.id {
            document.lastSessionID = session.id
            if allowStart, document.collectFocus, session.phase == .running, session.remaining(at: date) > 0 {
                var digest = BadgeFocusDigest(id: session.id, modeName: session.modeName, started: date)
                for path in current.keys.sorted().prefix(100) {
                    let value = current[path] ?? .unknown
                    digest.rows[path] = BadgeDigestRow(first: value, last: value, hasGap: value == .unknown)
                }
                document.active = digest
            }
        }
        if session?.phase == .paused, document.active != nil { document.active?.incomplete = true }
        prune(at: date)
        if before != document { persist() }
    }

    private func collect(path: String, value: BadgeObservation) {
        guard session?.phase == .running, var active = document.active else { return }
        if var row = active.rows[path] {
            if row.last != value { row.last = value; row.changes = min(1_000_000, row.changes + 1) }
            if value == .unknown { row.hasGap = true }
            active.rows[path] = row
        } else if value.label != nil, active.rows.count < 100 {
            active.rows[path] = BadgeDigestRow(first: .unknown, last: value, changes: 1, hasGap: true)
        }
        document.active = active
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

    /// Disabling stops collection immediately. Enabling applies to the next newly started session.
    func setCollectFocus(_ enabled: Bool) {
        guard !requiresReset else { return }
        document.collectFocus = enabled
        if !enabled, var active = document.active {
            active.ended = .now; active.incomplete = true
            document.digests.insert(active, at: 0); document.active = nil
        }
        prune(at: .now); persist()
    }

    func deleteDigest(_ id: UUID) {
        guard !requiresReset else { return }
        document.digests.removeAll { $0.id == id }
        if document.active?.id == id { document.active = nil }
        persist()
    }

    func clearApp(_ path: String) {
        guard !requiresReset else { return }
        document.apps[path] = nil
        document.active?.rows[path] = nil
        for index in document.digests.indices { document.digests[index].rows[path] = nil }
        persist()
    }

    /// Deletes all retained data, stops this session's collection and disables future collection.
    func clearAll() {
        document = BadgeMemoryDocument(lastSessionID: session?.id)
        requiresReset = false; storageFailed = false
        defaults.removeObject(forKey: Self.key)
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
        document.digests = Array(document.digests.filter { ($0.ended ?? $0.started) >= cutoff }.prefix(10))
        if let active = document.active, active.started < cutoff { document.active = nil }
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(document), forKey: Self.key)
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
        func digestValid(_ digest: BadgeFocusDigest) -> Bool {
            digest.rows.count <= 100 && digest.modeName.count <= 1024 && dateValid(digest.started)
                && (digest.ended.map(dateValid) ?? true) && digest.rows.allSatisfy { path, row in
                    pathValid(path) && valueValid(row.first) && valueValid(row.last) && (0...1_000_000).contains(row.changes)
                }
        }
        return doc.apps.count <= 100 && doc.digests.count <= 10 && (doc.active.map(digestValid) ?? true)
            && doc.digests.allSatisfy(digestValid) && doc.apps.allSatisfy { path, app in
                pathValid(path) && dateValid(app.touched) && app.changes.count <= 20
                    && app.changes.allSatisfy { valueValid($0.value) && dateValid($0.date) }
                    && (app.checked.map { valueValid($0.value) && dateValid($0.date) } ?? true)
            }
    }
}
