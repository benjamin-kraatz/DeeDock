import Foundation
import Observation

/// Cancellation handle for a deadline or animation frame; cancellation never runs the action.
@MainActor final class DockScheduledAction {
    var cancelAction: (() -> Void)?
    func cancel() { cancelAction?(); cancelAction = nil }
}

/// An injected monotonic scheduler lets tests advance deadlines without sleeping or opening windows.
@MainActor protocol DockVisibilityScheduling {
    var now: TimeInterval { get }
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> DockScheduledAction
}

@MainActor final class DockVisibilityScheduler: DockVisibilityScheduling {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> DockScheduledAction {
        let handle = DockScheduledAction()
        let task = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(max(0, delay))) } catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
        handle.cancelAction = { task.cancel() }
        return handle
    }
}

/// One panel's deadlines and finite animation ticks. No scheduled work remains while settled and idle.
@MainActor @Observable final class DockVisibilityController {
    private(set) var progress: Double
    /// Fully hidden presentation is absent from both pointer targets and the accessibility tree.
    var exposesContent: Bool { progress < 1 }
    private(set) var phase: DockVisibilityState.Phase
    private(set) var settings: DockBehaviorSettings
    private(set) var reduceMotion: Bool
    /// Native owners resample the actual pointer before a delayed action; tests can supply stored input.
    @ObservationIgnored var refreshInput: (() -> Void)?
    @ObservationIgnored var didChange: (() -> Void)?
    @ObservationIgnored private var model: DockVisibilityState
    @ObservationIgnored private let scheduler: any DockVisibilityScheduling
    @ObservationIgnored private var scheduled: DockScheduledAction?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var active = true
    @ObservationIgnored private var processing = false
    @ObservationIgnored private var activation = false
    @ObservationIgnored private var retained = false
    @ObservationIgnored private var held = false

    init(settings: DockBehaviorSettings? = nil, reduceMotion: Bool = false,
         scheduler: (any DockVisibilityScheduling)? = nil) {
        let settings = settings ?? DockBehaviorSettings()
        self.settings = settings
        self.reduceMotion = reduceMotion
        self.scheduler = scheduler ?? DockVisibilityScheduler()
        model = DockVisibilityState(settings: settings, reduceMotion: reduceMotion)
        progress = settings.autoHide ? 1 : 0
        phase = model.phase
    }
    func update(activation: Bool, retained: Bool, held: Bool) {
        self.activation = activation; self.retained = retained; self.held = held
        process { $0.update(activation: activation, retained: retained, held: held, now: scheduler.now) }
    }
    func configure(_ settings: DockBehaviorSettings, reduceMotion: Bool, geometryChanged: Bool = false) {
        guard self.settings != settings || self.reduceMotion != reduceMotion || geometryChanged else { return }
        self.settings = settings; self.reduceMotion = reduceMotion
        process { $0.configure(settings, reduceMotion: reduceMotion) }
    }
    func showImmediately() { process { $0.showImmediately() } }

    private func process(_ change: (inout DockVisibilityState) -> Void) {
        guard active, !processing else { return }
        processing = true
        scheduled?.cancel()
        scheduled = nil
        generation = UUID()
        change(&model)
        progress = model.progress(at: scheduler.now)
        phase = model.phase
        didChange?()
        if let time = model.nextUpdate(after: scheduler.now) {
            let token = generation
            scheduled = scheduler.schedule(after: max(0, time - scheduler.now)) { [weak self] in
                guard let self, active, generation == token else { return }
                if let refreshInput { refreshInput() }
                else {
                    process { state in
                        state.update(activation: self.activation, retained: self.retained, held: self.held, now: self.scheduler.now)
                    }
                }
            }
        }
        processing = false
    }
    /// Invalidates even a callback already delivered by an uncooperative scheduler.
    func stop() {
        active = false; generation = UUID(); scheduled?.cancel(); scheduled = nil
        model.stop(); progress = 1; phase = .hidden; didChange = nil; refreshInput = nil
    }
}
