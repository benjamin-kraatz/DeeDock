import ServiceManagement

/// Uses the main app's registration, with no helper executable or stored preference.
@MainActor
final class SystemLoginItemService: LoginItemServicing {
    private let service = SMAppService.mainApp

    var status: LoginItemStatus { LoginItemStatus(service.status) }
    func register() throws { try service.register() }
    func unregister() async throws { try await service.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

extension LoginItemStatus {
    init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .notRegistered
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        @unknown default: self = .unknown
        }
    }
}
