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
    func timeLabel(at date: Date) -> String {
        let seconds = Int(ceil(remaining(at: date)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
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
}

struct FocusDockItem {
    let session: FocusSession
    let celebrationID: UUID?
}
