import Foundation

/// Registration and approval are separate: only `enabled` permits automatic startup.
enum LoginItemStatus: CaseIterable, Sendable {
    case notRegistered, enabled, requiresApproval, notFound, unknown

    var isEnabled: Bool { self == .enabled }
    var canToggle: Bool { self == .notRegistered || self == .enabled }
}

/// The app owns this service; reading status never registers or launches anything.
@MainActor
protocol LoginItemServicing: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    /// Completion reports the OS handoff. Unregistering the main app does not quit it.
    func unregister() async throws
    func openSystemSettings()
}
