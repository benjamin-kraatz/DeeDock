import Foundation
import Observation

/// Bounds a temporary preview; replacement, scope changes, and stale expiry callbacks cannot close a newer lease.
@MainActor @Observable final class DockPreviewLease {
    private(set) var displayID: String?
    @ObservationIgnored var didEnd: (() -> Void)?
    @ObservationIgnored private let scheduler: any DockVisibilityScheduling
    @ObservationIgnored private var expiration: DockScheduledAction?
    @ObservationIgnored private var generation = UUID()
    init(scheduler: any DockVisibilityScheduling) { self.scheduler = scheduler }
    func begin(displayID: String) {
        stop()
        self.displayID = displayID
        let token = generation
        expiration = scheduler.schedule(after: 10) { [weak self] in
            guard self?.generation == token else { return }
            self?.stop()
        }
    }
    func stop() {
        generation = UUID(); expiration?.cancel(); expiration = nil
        let hadPreview = displayID != nil
        displayID = nil
        if hadPreview { didEnd?() }
    }
}
