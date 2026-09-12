import Foundation

/// Local, opt-in count of promised sessions ended before their remaining time reaches zero.
/// Only a session started while enabled is a promise. Disabling forgets that promise and the count.
nonisolated struct FocusDebtState: Codable, Equatable, Sendable {
    private(set) var enabled = false
    private(set) var count = 0
    private(set) var promisedSessionID: UUID?

    var isValid: Bool { count >= 0 && (enabled || (count == 0 && promisedSessionID == nil)) }

    mutating func configure(enabled: Bool) {
        if enabled { self.enabled = true }
        else { self = FocusDebtState() }
    }

    mutating func begin(sessionID: UUID) {
        promisedSessionID = enabled ? sessionID : nil
    }

    /// Consume the promise even on natural completion so later dismissal cannot count it again.
    mutating func end(_ session: FocusSession, at date: Date) {
        guard enabled, promisedSessionID == session.id else { return }
        promisedSessionID = nil
        if session.phase != .completed, session.remaining(at: date) > 0, count < Int.max {
            count += 1
        }
    }
}
