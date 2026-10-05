import Foundation

/// A shared wall-clock deadline. Sleep and application downtime count toward a running session.
nonisolated struct FocusSession: Codable, Equatable, Identifiable, Sendable {
    enum Phase: String, Codable, Sendable { case running, paused, completed }
    let id: UUID
    let modeID: UUID
    let modeName: String
    var duration: TimeInterval
    var remainingWhenPaused: TimeInterval
    var deadline: Date?
    var phase: Phase

    func remaining(at date: Date) -> TimeInterval {
        switch phase {
        case .running: min(duration, max(0, deadline?.timeIntervalSince(date) ?? 0))
        case .paused: remainingWhenPaused
        case .completed: 0
        }
    }
    func fraction(at date: Date) -> Double { min(1, max(0, remaining(at: date) / max(1, duration))) }

    /// Countdown text. Under an hour this is `MM:SS`. At an hour or more it is `H:MM:SS`, with the hour unpadded.
    func timeLabel(at date: Date) -> String {
        let seconds = displaySeconds(at: date)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remainder) }
        return String(format: "%02d:%02d", minutes, remainder)
    }

    /// Whether ``timeLabel(at:)`` includes an hour. Glyphs use this to scale only the longer string.
    func showsHours(at date: Date) -> Bool { displaySeconds(at: date) >= 3_600 }

    /// Remaining time in words for VoiceOver, in the current locale, for the same whole seconds as ``timeLabel(at:)``.
    func spokenRemaining(at date: Date) -> String {
        let seconds = displaySeconds(at: date)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .spellOut
        formatter.allowedUnits = seconds == 0 ? [.second] : [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = seconds == 0 ? .pad : .dropAll
        let spoken = formatter.string(from: TimeInterval(seconds))
        if let spoken, !spoken.isEmpty { return spoken }
        return timeLabel(at: date)
    }

    /// Whole seconds still to run, rounded up so a visible second is not dropped early.
    private func displaySeconds(at date: Date) -> Int {
        Int(ceil(remaining(at: date)))
    }
    var isValid: Bool {
        !modeName.isEmpty && duration.isFinite && (60...86400).contains(duration)
            && remainingWhenPaused.isFinite && (0...duration).contains(remainingWhenPaused)
            && (phase != .running || (deadline != nil && deadline!.timeIntervalSince1970.isFinite))
            && (phase == .running || deadline == nil)
    }
}

nonisolated struct FocusSessionsDocument: Codable {
    var version = 1
    var minutes = 25
    var celebrates = false
    var session: FocusSession?
    var bossFight: BossFightConfiguration?
    var focusDebt: FocusDebtState?
}

struct FocusDockItem {
    let session: FocusSession
    let celebrationID: UUID?
    var bossFightEnabled = false
    var bossVictoryID: UUID?
}
