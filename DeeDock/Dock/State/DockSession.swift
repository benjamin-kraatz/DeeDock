import Foundation

/// Invalidates completion delivery when a panel is disabled, disconnected, or replaced.
struct DockSession {
    private(set) var token = UUID()
    private(set) var isActive = true
    func accepts(_ token: UUID) -> Bool { isActive && token == self.token }
    mutating func stop() { isActive = false; token = UUID() }
}
