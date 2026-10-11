// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Foundation
import IOKit.ps
import os

/// When the big first pass (backfill) may run: with the Mac cool (thermal state nominal or fair), not in Low Power
/// Mode, and on AC power if "Read files on battery too" is off (it's on by default). A few new files always index
/// right away; they take seconds. The app decides and tells the index service (`setBackfillAllowed`).
///
/// Event-driven: power-source, thermal and Low Power Mode changes re-evaluate; nothing polls. Observers and the IOKit
/// run-loop source exist only between `start` and `stop` (or deinit).
@MainActor final class LookoutPowerPolicy: LookoutPowerPolicing {
    private var indexOnBattery = true
    private var onChange: ((LookoutBackfillBlocker?) -> Void)?
    private var powerSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private(set) var blocker: LookoutBackfillBlocker?

    init() {}

    isolated deinit {
        stop()
    }

    func start(indexOnBattery: Bool, onChange: @escaping (LookoutBackfillBlocker?) -> Void) {
        stop()
        self.indexOnBattery = indexOnBattery
        self.onChange = onChange
        blocker = Self.currentBlocker(indexOnBattery: indexOnBattery)
        // The source calls back on the main run loop with this unretained pointer; `stop` removes it before the
        // policy can go away.
        let me = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(lookoutPowerSourceChanged, me)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.reevaluate() }
            })
        }
    }

    func setIndexOnBattery(_ indexOnBattery: Bool) {
        self.indexOnBattery = indexOnBattery
        reevaluate()
    }

    func stop() {
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        onChange = nil
    }

    fileprivate func reevaluate() {
        let now = Self.currentBlocker(indexOnBattery: indexOnBattery)
        guard now != blocker else { return }
        blocker = now
        LookoutLog.logger.info("Backfill \(now.map { "waits (\($0.rawValue))" } ?? "may run", privacy: .public)")
        onChange?(now)
    }

    /// Why the backfill has to wait, from the machine's state: the pure rule `currentBlocker` applies.
    nonisolated static func backfillBlocker(lowPowerMode: Bool, thermalState: ProcessInfo.ThermalState,
                                            onACPower: Bool, indexOnBattery: Bool) -> LookoutBackfillBlocker? {
        if lowPowerMode { return .lowPowerMode }
        switch thermalState {
        case .serious, .critical: return .warm
        default: break
        }
        if !indexOnBattery, !onACPower { return .onBattery }
        return nil
    }

    /// Why the backfill has to wait right now.
    nonisolated static func currentBlocker(indexOnBattery: Bool) -> LookoutBackfillBlocker? {
        let info = ProcessInfo.processInfo
        // Only look the power source up when it matters.
        return backfillBlocker(lowPowerMode: info.isLowPowerModeEnabled, thermalState: info.thermalState,
                               onACPower: indexOnBattery || onACPower(), indexOnBattery: indexOnBattery)
    }

    nonisolated static func onACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?
        else { return true }   // no power-source info: a desktop Mac
        return type == kIOPMACPowerKey
    }
}

/// IOKit calls this on the main run loop when the power source changes.
private nonisolated func lookoutPowerSourceChanged(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        Unmanaged<LookoutPowerPolicy>.fromOpaque(UnsafeRawPointer(bitPattern: address)!).takeUnretainedValue()
            .reevaluate()
    }
}
