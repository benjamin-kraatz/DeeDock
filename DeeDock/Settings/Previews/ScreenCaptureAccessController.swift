import Observation

/// Mirrors macOS Screen Recording authorization without storing a second preference.
@MainActor @Observable
final class ScreenCaptureAccessController {
    private(set) var status: ScreenCaptureAccessStatus
    @ObservationIgnored private let service: any ScreenCaptureAccessServicing
    @ObservationIgnored private var stopped = false

    init(service: any ScreenCaptureAccessServicing) {
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
        Analytics.track(.permissionChanged(.screenRecording, status: AnalyticsPermissionStatus(status)))
        Analytics.shared.contextDidChange()
    }

    func requestAccess() {
        guard !stopped, status != .enabled else { return }
        Analytics.track(.permissionRequested(.screenRecording))
        service.requestAccess()
        refresh()
    }

    func openSystemSettings() {
        guard !stopped else { return }
        service.openSystemSettings()
    }

    func stop() { stopped = true }
}
