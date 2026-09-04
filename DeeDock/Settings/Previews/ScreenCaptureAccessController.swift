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

    func refresh() {
        guard !stopped else { return }
        status = service.status
    }

    func requestAccess() {
        guard !stopped, status != .enabled else { return }
        service.requestAccess()
        refresh()
    }

    func openSystemSettings() {
        guard !stopped else { return }
        service.openSystemSettings()
    }

    func stop() { stopped = true }
}
