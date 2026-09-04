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
