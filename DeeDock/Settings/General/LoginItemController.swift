import Foundation
import Observation

/// Serializes explicit requests for the app lifetime, independently of Settings windows.
@MainActor @Observable
final class LoginItemController {
    enum Operation { case register, unregister, cancelRequest }

    private(set) var status: LoginItemStatus
    private(set) var pendingOperation: Operation?
    private(set) var errorMessage: LocalizedStringResource?
    var isPending: Bool { pendingOperation != nil }
    var canToggle: Bool { !stopped && !isPending && status.canToggle }

    @ObservationIgnored private let service: any LoginItemServicing
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var stopped = false

    init(service: any LoginItemServicing) {
        self.service = service
        status = service.status
    }

    /// Called on startup, pane appearance and Settings window activation; never polls.
    func refresh() {
        guard !stopped else { return }
        status = service.status
    }

    /// Returns the owned request for callers that need to await completion; nil means no work.
    /// The status remains the OS's last reported value while a request is in flight.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Task<Void, Never>? {
        guard !stopped, !isPending else { return nil }
        refresh()
        guard status.canToggle, enabled != status.isEnabled else { return nil }
        return perform(enabled ? .register : .unregister)
    }

    /// Withdraws a pending approval using the same asynchronous unregistration path.
    @discardableResult
    func cancelRequest() -> Task<Void, Never>? {
        guard !stopped, !isPending else { return nil }
        refresh()
        guard status == .requiresApproval else { return nil }
        return perform(.cancelRequest)
    }

    func openSystemSettings() {
        guard !stopped else { return }
        service.openSystemSettings()
    }

    func dismissError() { errorMessage = nil }

    /// Shutdown invalidates callbacks; a request already submitted to macOS cannot be undone.
    func stop() {
        stopped = true
        generation = UUID()
        task?.cancel()
        task = nil
        pendingOperation = nil
    }

    private func perform(_ operation: Operation) -> Task<Void, Never> {
        pendingOperation = operation
        errorMessage = nil
        let request = UUID()
        generation = request
        let service = service
        // Capture the service across suspension, not the controller. Closing Settings has
        // no bearing on this task; shutdown is the only owner-driven cancellation point.
        let work = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            var failure: LocalizedStringResource?
            do {
                switch operation {
                case .register: try service.register()
                case .unregister, .cancelRequest: try await service.unregister()
                }
            } catch {
                switch operation {
                case .register: failure = .loginRegistrationError(reason: error.localizedDescription)
                case .unregister: failure = .loginUnregistrationError(reason: error.localizedDescription)
                case .cancelRequest: failure = .loginCancellationError(reason: error.localizedDescription)
                }
            }
            guard let self, !self.stopped, self.generation == request else { return }
            // Errors can still accompany an OS status change. Never infer the resulting
            // registration from either the requested value or the completion's success.
            self.refresh()
            self.errorMessage = failure
            self.pendingOperation = nil
            self.task = nil
        }
        task = work
        return work
    }
}
