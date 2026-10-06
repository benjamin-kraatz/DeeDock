import AppKit
import Observation

/// Owns the one-click switch that tucks the macOS Dock away and puts it back.
///
/// Lifecycle: `start()` once after the docks exist, `restoreForTermination()` from
/// `applicationWillTerminate`, `stop()` with the coordinator. The switch survives quits; the
/// person's previous values survive crashes, in `SystemDockTuckRecord.snapshot`.
///
/// Invariants that keep a person able to get their Dock back:
/// - The snapshot is saved before the first write and cleared only after a restore persisted.
/// - A value is restored only while it still holds what DOKK wrote; a change the person made
///   in System Settings meanwhile is theirs to keep.
/// - A failed write rolls back what it can. Whatever remains is still covered by the snapshot,
///   and the Restore button stays available while a snapshot exists.
///
/// Analytics: every action sends one `system_dock_tuck` event. A click also sends
/// `setting_changed` for `system_dock_tuck` when the switch flips. Launch and edge-following
/// actions report only when they wrote something or failed, so an ordinary launch stays quiet.
@MainActor @Observable
final class SystemDockTuckController {
    enum Failure: Equatable {
        case managed, snapshot, write, restore

        var message: LocalizedStringResource {
            switch self {
            case .managed: .systemDockTuckFailedManaged
            case .snapshot: .systemDockTuckFailedSnapshot
            case .write: .systemDockTuckFailedWrite
            case .restore: .systemDockRestoreFailed
            }
        }

        var analytics: AnalyticsSystemDockTuckFailure {
            switch self {
            case .managed: .managed
            case .snapshot: .snapshot
            case .write: .write
            case .restore: .restore
            }
        }
    }

    /// What one action did, collected while it runs and reported when it ends.
    private struct Trace {
        var restarted = false
        /// Keys a restore left alone because the person changed them.
        var kept = 0
        var failure: Failure?
    }

    /// The person's choice; it stays on across quits.
    private(set) var isOn = false
    /// The side DOKK put the Dock on, or nil while DOKK's values are not in place.
    private(set) var tuckedOrientation: SystemDockOrientation?
    private(set) var failure: Failure?

    /// DOKK's resolved edge on the main display. A change that moves the Dock to the other
    /// side is applied after a short pause, so stepping through edges restarts the Dock once.
    @ObservationIgnored var mainDockEdge: DockEdge? {
        didSet {
            guard SystemDockOrientation.avoiding(mainDockEdge) != SystemDockOrientation.avoiding(oldValue) else { return }
            scheduleOrientationFollow()
        }
    }

    @ObservationIgnored private let service: SystemDockPreferencesServicing
    @ObservationIgnored private let repository: SystemDockTuckRepository
    @ObservationIgnored private var record = SystemDockTuckRecord()
    @ObservationIgnored private var started = false
    /// The pending orientation change, readable so tests can await it instead of guessing
    /// how long the pause takes on a busy main actor.
    @ObservationIgnored private(set) var followTask: Task<Void, Never>?
    @ObservationIgnored private var powerOffObserver: NSObjectProtocol?
    /// Logout, restart, and shutdown still restore the values, but restarting the Dock inside
    /// an ending session only produces a flash; the next login reads the restored values.
    @ObservationIgnored private var sessionEnding = false
    /// Held while DOKK's values are in place, so macOS asks DOKK to quit (and restore) instead
    /// of killing it at logout.
    @ObservationIgnored private var suddenTerminationDisabled = false
    @ObservationIgnored private var trace = Trace()
    @ObservationIgnored private let track: (AnalyticsEvent) -> Void
    @ObservationIgnored private let settingChanged: (_ from: Bool, _ to: Bool) -> Void

    /// Constructing the controller reads DOKK's record, and the Dock's values only when that
    /// record is unreadable. It writes nothing; `start()` acts on the record.
    ///
    /// - Parameters:
    ///   - service: the Dock's preferences; nil uses the live `com.apple.dock` domain.
    ///   - repository: where the record lives; nil uses standard user defaults.
    ///   - track: receives each `system_dock_tuck` event; nil sends it to PostHog.
    ///   - settingChanged: receives a click's switch change; nil reports `setting_changed`.
    init(service: SystemDockPreferencesServicing? = nil, repository: SystemDockTuckRepository? = nil,
         track: ((AnalyticsEvent) -> Void)? = nil, settingChanged: ((Bool, Bool) -> Void)? = nil) {
        self.service = service ?? SystemDockPreferences()
        self.repository = repository ?? SystemDockTuckRepository()
        self.track = track ?? { Analytics.track($0) }
        self.settingChanged = settingChanged ?? { old, new in
            Analytics.shared.featureSettingChanged(.systemDockTuck, from: AnalyticsValue(old), to: AnalyticsValue(new))
        }
        loadRecord()
    }

    /// Whether DOKK's values are in place, which is when Restore is offered.
    var isTucked: Bool { tuckedOrientation != nil }

    /// Re-applies the switch at launch, or finishes a restore a crash or failure interrupted.
    ///
    /// Already-correct values (after a crash, for example) are left alone, so this restarts
    /// the Dock only when something actually changes.
    func start() {
        guard !started else { return }
        started = true
        powerOffObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.sessionEnding = true } }
        if record.isOn {
            perform(.reapplyOnLaunch, source: .automatic, reportsUnchanged: false) {
                apply(SystemDockOrientation.avoiding(mainDockEdge))
            }
        } else if record.snapshot != nil {
            perform(.resumeRestore, source: .automatic) { restoreValues(keepingSwitch: false) }
        }
    }

    /// Cancels pending work and observers. Does not restore; quitting does that explicitly.
    func stop() {
        followTask?.cancel()
        followTask = nil
        if let powerOffObserver { NSWorkspace.shared.notificationCenter.removeObserver(powerOffObserver) }
        powerOffObserver = nil
        started = false
    }

    /// Turns the switch on and tucks the Dock away.
    /// - Parameter source: where the click happened, for analytics.
    func tuckAway(source: AnalyticsSystemDockTuckSource = .settings) {
        failure = nil
        perform(.tuckAway, source: source) { apply(SystemDockOrientation.avoiding(mainDockEdge)) }
    }

    /// Turns the switch off and puts the person's values back.
    /// - Parameter source: where the click happened, for analytics.
    func restore(source: AnalyticsSystemDockTuckSource = .settings) {
        failure = nil
        followTask?.cancel()
        perform(.restore, source: source) { restoreValues(keepingSwitch: false) }
    }

    /// Puts the person's values back on quit while keeping the switch on for the next launch.
    /// Synchronous, because the process ends when `applicationWillTerminate` returns. Its event
    /// is queued before `Analytics.stop()` flushes at quit.
    func restoreForTermination() {
        followTask?.cancel()
        guard record.snapshot != nil else { return }
        perform(.restoreOnQuit, source: .automatic) { restoreValues(keepingSwitch: true) }
    }

    func dismissFailure() { failure = nil }

    // MARK: - Applying

    private func apply(_ orientation: SystemDockOrientation) {
        // Fresh reads: the person may have changed the Dock since DOKK last looked.
        _ = service.synchronize()
        if SystemDockKey.allCases.contains(where: { service.isManaged($0) }) {
            return fail(.managed, turningOff: true)
        }
        var snapshot = record.snapshot ?? SystemDockSnapshot(originals: [:], orientation: orientation)
        do {
            for key in SystemDockKey.allCases {
                let current = service.value(for: key)
                // Capture every key on the first tuck; afterwards, only keys the person changed
                // since DOKK wrote them. Their new value is what a restore should return to.
                let written = SystemDockTuckPlan.value(for: key, orientation: snapshot.orientation)
                guard record.snapshot == nil || !written.matches(current) else { continue }
                snapshot.originals[key.rawValue] = try SystemDockSnapshot.archive(current)
            }
        } catch {
            return fail(.snapshot, turningOff: record.snapshot == nil)
        }
        snapshot.orientation = orientation
        // Saved before any write: from here on, a crash still leaves a way back.
        guard repository.save(SystemDockTuckRecord(isOn: true, snapshot: snapshot)) else {
            return fail(.snapshot, turningOff: record.snapshot == nil)
        }
        record = SystemDockTuckRecord(isOn: true, snapshot: snapshot)

        var changed = false
        for key in SystemDockKey.allCases {
            let target = SystemDockTuckPlan.value(for: key, orientation: orientation)
            guard !target.matches(service.value(for: key)) else { continue }
            service.setValue(target.propertyList, for: key)
            changed = true
        }
        if changed {
            let persisted = service.synchronize() && SystemDockKey.allCases.allSatisfy {
                SystemDockTuckPlan.value(for: $0, orientation: orientation).matches(service.value(for: $0))
            }
            guard persisted else {
                restoreValues(keepingSwitch: false)
                // The rollback skips keys whose write never landed; they are not the person's.
                trace.kept = 0
                return fail(.write, turningOff: false)
            }
            restartDockUnlessSessionEnding()
        }
        publish()
    }

    /// Follows DOKK onto or off the left edge. Only the orientation key moves, and only while
    /// it still holds what DOKK wrote.
    private func scheduleOrientationFollow() {
        followTask?.cancel()
        guard started, record.isOn, record.snapshot != nil else { return }
        followTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self else { return }
            followTask = nil
            perform(.followEdge, source: .automatic, reportsUnchanged: false) { self.followOrientation() }
        }
    }

    private func followOrientation() {
        guard record.isOn, var snapshot = record.snapshot else { return }
        let target = SystemDockOrientation.avoiding(mainDockEdge)
        guard target != snapshot.orientation else { return }
        _ = service.synchronize()
        let written = SystemDockTuckPlan.value(for: .orientation, orientation: snapshot.orientation)
        // The person moved the Dock themselves; leave it where they put it.
        guard written.matches(service.value(for: .orientation)) else { return }
        let previous = record
        snapshot.orientation = target
        let next = SystemDockTuckRecord(isOn: true, snapshot: snapshot)
        guard repository.save(next) else { return }
        record = next
        service.setValue(SystemDockTuckPlan.value(for: .orientation, orientation: target).propertyList, for: .orientation)
        guard service.synchronize() else {
            // The Dock kept its old side, so the record has to say so too; otherwise a restore
            // would mistake DOKK's own value for one the person chose.
            service.setValue(written.propertyList, for: .orientation)
            record = previous
            repository.save(previous)
            return fail(.write, turningOff: false)
        }
        restartDockUnlessSessionEnding()
        publish()
    }

    // MARK: - Restoring

    private func restoreValues(keepingSwitch: Bool) {
        guard let snapshot = record.snapshot else {
            record.isOn = keepingSwitch && record.isOn
            repository.save(record)
            return publish()
        }
        _ = service.synchronize()
        var changed = false
        for key in SystemDockKey.allCases {
            let written = SystemDockTuckPlan.value(for: key, orientation: snapshot.orientation)
            // Changed by the person since DOKK wrote it: theirs to keep.
            guard written.matches(service.value(for: key)) else {
                trace.kept += 1
                continue
            }
            let original = snapshot.original(for: key)
            service.setValue(original, for: key)
            if !written.matches(original) { changed = true }
        }
        guard service.synchronize() else {
            // The snapshot stays, so Restore remains available and the next launch retries.
            record.isOn = keepingSwitch && record.isOn
            repository.save(record)
            return fail(.restore, turningOff: false)
        }
        if changed { restartDockUnlessSessionEnding() }
        record = SystemDockTuckRecord(isOn: keepingSwitch && record.isOn, snapshot: nil)
        repository.save(record)
        publish()
    }

    // MARK: - State

    private func restartDockUnlessSessionEnding() {
        guard !sessionEnding else { return }
        service.restartDock()
        trace.restarted = true
    }

    /// Runs one action and reports it.
    ///
    /// - Parameter reportsUnchanged: false for follow-through that usually finds nothing to do,
    ///   which then reports only when it restarted the Dock or failed.
    private func perform(_ action: AnalyticsSystemDockTuckAction, source: AnalyticsSystemDockTuckSource,
                         reportsUnchanged: Bool = true, _ body: () -> Void) {
        trace = Trace()
        let wasOn = record.isOn
        body()
        if source != .automatic, wasOn != record.isOn { settingChanged(wasOn, record.isOn) }
        guard reportsUnchanged || trace.restarted || trace.failure != nil else { return }
        let outcome: AnalyticsOutcome = switch trace.failure {
        case nil: .succeeded
        case .managed?: .blocked
        case _?: .failed
        }
        track(.systemDockTuck(action, source: source, outcome: outcome, failure: trace.failure?.analytics,
                              side: record.snapshot?.orientation, dockRestarted: trace.restarted,
                              keptCount: trace.kept))
    }

    private func fail(_ failure: Failure, turningOff: Bool) {
        if turningOff, record.isOn {
            record.isOn = false
            repository.save(record)
        }
        self.failure = failure
        trace.failure = failure
        publish()
    }

    private func loadRecord() {
        if let loaded = repository.load() {
            record = loaded
        } else {
            // DOKK lost track of what it changed. If the Dock still carries DOKK's values,
            // treat macOS's defaults as the way back: `start()` finishes that restore, so an
            // unreadable record errs toward a visible Dock rather than a hidden one.
            let orientation = (service.value(for: .orientation) as? String)
                .flatMap(SystemDockOrientation.init(rawValue:)) ?? .left
            let tucked = SystemDockKey.allCases.allSatisfy {
                SystemDockTuckPlan.value(for: $0, orientation: orientation).matches(service.value(for: $0))
            }
            record = SystemDockTuckRecord(
                isOn: false, snapshot: tucked ? SystemDockSnapshot(originals: [:], orientation: orientation) : nil)
        }
        publish()
    }

    private func publish() {
        let changed = isOn != record.isOn || tuckedOrientation != record.snapshot?.orientation
        isOn = record.isOn
        tuckedOrientation = record.snapshot?.orientation
        // Every event carries the switch and the side; launch and quit change them without a click.
        if changed { Analytics.shared.contextDidChange() }
        if record.snapshot != nil, !suddenTerminationDisabled {
            ProcessInfo.processInfo.disableSuddenTermination()
            suddenTerminationDisabled = true
        } else if record.snapshot == nil, suddenTerminationDisabled {
            ProcessInfo.processInfo.enableSuddenTermination()
            suddenTerminationDisabled = false
        }
    }
}
