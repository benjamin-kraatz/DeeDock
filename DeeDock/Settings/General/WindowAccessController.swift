import Observation

/// App-wide view state mirrors macOS authorization and never stores a second preference.
@MainActor @Observable
final class WindowAccessController {
    private(set) var status: WindowAccessStatus
    @ObservationIgnored private let service: any WindowAccessServicing
    @ObservationIgnored private var stopped = false

    init(service: any WindowAccessServicing) {
        self.service = service
        status = service.status
    }

    /// Reads the status macOS reports. A change seen while DOKK runs is reported to analytics,
    /// which also refreshes the permission properties registered on every event.
    func refresh() {
        guard !stopped else { return }
        let previous = status
        status = service.status
        guard status != previous else { return }
        Analytics.track(.permissionChanged(.accessibility, status: AnalyticsPermissionStatus(status)))
        Analytics.shared.contextDidChange()
    }

    func requestAccess() {
        guard !stopped, status != .enabled else { return }
        Analytics.track(.permissionRequested(.accessibility))
        service.requestAccess()
        refresh()
    }

    func openSystemSettings() {
        guard !stopped else { return }
        service.openSystemSettings()
    }

    func stop() { stopped = true }
}
