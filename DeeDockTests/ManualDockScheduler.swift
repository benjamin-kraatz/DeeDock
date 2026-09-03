import Foundation

/// Runs only when a test advances time. Retained callbacks deliberately simulate cancellation races.
@MainActor final class ManualDockScheduler: DockVisibilityScheduling {
    private struct Job { let time: TimeInterval; let action: @MainActor () -> Void }
    private(set) var now: TimeInterval = 0
    private var jobs: [UUID: Job] = [:]
    private var callbacks: [UUID: @MainActor () -> Void] = [:]
    private(set) var lastID: UUID?
    var pendingCount: Int { jobs.count }
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> DockScheduledAction {
        let id = UUID(); lastID = id
        jobs[id] = Job(time: now + delay, action: action); callbacks[id] = action
        let handle = DockScheduledAction()
        handle.cancelAction = { [weak self] in self?.jobs[id] = nil }
        return handle
    }
    func advance(to time: TimeInterval) {
        while let next = jobs.min(by: { $0.value.time < $1.value.time }), next.value.time <= time {
            now = next.value.time; jobs[next.key] = nil; next.value.action()
        }
        now = time
    }
    func deliverStale(_ id: UUID) { callbacks[id]?() }
}
