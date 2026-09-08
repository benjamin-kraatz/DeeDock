import Foundation

/// Pure observation state. Only a sustained activation is a target; launches and quits merely
/// update context. Session boundaries discard pending outcomes and never reconstruct gaps.
nonisolated struct LauncherSuggestionRecorder {
    static let dwell: TimeInterval = 3
    static let sessionGap: TimeInterval = 300
    private(set) var foregroundID: String?
    private var foregroundSince: Date?
    private var recentIDs: [String] = []
    private var lastUse: [String: Date] = [:]
    private var lastTermination: [String: Date] = [:]
    private var runningIDs: [String] = []
    private var pending: (id: String, context: LauncherSuggestionContext, date: Date)?
    private var sessionStarted: Date?

    mutating func begin(now: Date, foregroundID: String?, runningIDs: [String]) {
        self = Self()
        sessionStarted = now
        self.foregroundID = foregroundID
        foregroundSince = foregroundID == nil ? nil : now
        self.runningIDs = Array(Set(runningIDs).sorted().prefix(128))
    }

    func context(now: Date, modeID: String?) -> LauncherSuggestionContext {
        let calendar = Calendar.autoupdatingCurrent
        // Public idle/session signals cannot establish active-use duration through every lock
        // state. Omit this optional feature instead of labeling unattended time as active use.
        let duration: Double? = nil
        return LauncherSuggestionContext(date: now, foregroundID: foregroundID, modeID: modeID,
            recentIDs: recentIDs, runningIDs: runningIDs,
            hour: calendar.component(.hour, from: now), weekday: calendar.component(.weekday, from: now),
            foregroundSeconds: duration,
            secondsSinceUse: lastUse.mapValues { max(0, now.timeIntervalSince($0)) },
            secondsSinceTermination: lastTermination.mapValues { max(0, now.timeIntervalSince($0)) })
    }

    mutating func launched(_ id: String, running: [String]) {
        runningIDs = Array(Set(running).sorted().prefix(128))
    }

    mutating func terminated(_ id: String, now: Date, running: [String]) {
        runningIDs = Array(Set(running).sorted().prefix(128))
        // One terminated helper process does not imply the app's last instance quit.
        guard !runningIDs.contains(id) else { return }
        lastTermination[id] = now
        trim(&lastTermination)
        if pending?.id == id { pending = nil }
        if foregroundID == id { foregroundID = nil; foregroundSince = nil }
    }

    mutating func activate(_ id: String?, now: Date, modeID: String?) {
        // DDock and unidentifiable/background helpers cannot be targets or erase the prior
        // context, but must cancel a pending accidental switch while they hold focus.
        guard let id else { pending = nil; return }
        guard id != foregroundID else { pending = nil; return }
        guard pending?.id != id else { return }
        pending = (id, context(now: now, modeID: modeID), now)
    }

    mutating func settle(now: Date) -> LauncherSuggestionExample? {
        guard let pending, now.timeIntervalSince(pending.date) >= Self.dwell else { return nil }
        self.pending = nil
        // Startup bursts cannot teach a chain inferred from an unobserved login period.
        let canLearn = sessionStarted.map { pending.date.timeIntervalSince($0) >= 5 } ?? false
        let old = foregroundID
        foregroundID = pending.id; foregroundSince = pending.date
        if let old { recentIDs = Array(([old] + recentIDs.filter { $0 != old }).prefix(3)) }
        lastUse[pending.id] = now
        trim(&lastUse)
        return canLearn ? LauncherSuggestionExample(context: pending.context, targetID: pending.id, date: now) : nil
    }

    mutating func stop() { self = Self() }

    private func trim(_ values: inout [String: Date]) {
        if values.count > 64 {
            let keep = Set(values.sorted { $0.value > $1.value }.prefix(64).map(\.key))
            values = values.filter { keep.contains($0.key) }
        }
    }
}
