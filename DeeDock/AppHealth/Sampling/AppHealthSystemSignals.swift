import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.ps

/// Machine-wide signals each tick records: idle time, power source, and the running-app snapshot.
///
/// Every read here is cheap and public. None prompts: Accessibility is checked with `AXIsProcessTrusted()`, never
/// with the prompting variant.
enum AppHealthSystemSignals {
    /// Builds the tick's snapshot from `NSWorkspace`. Main actor, because `NSWorkspace`'s running-app list is.
    ///
    /// Apps without a bundle identifier and terminated apps are skipped. DOKK itself is included, so its own cost
    /// appears in the data, but labelling never asks about it.
    static func snapshot(at date: Date, power: AppHealthPowerSource,
                         thermal: AppHealthThermalState) -> AppHealthSystemSnapshot {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications.compactMap { application -> AppHealthWatchedApp? in
            guard let bundleID = application.bundleIdentifier, !application.isTerminated else { return nil }
            return AppHealthWatchedApp(bundleID: bundleID, kind: AppHealthAppKind(application.activationPolicy),
                                       pid: application.processIdentifier,
                                       bundlePath: application.bundleURL?.standardizedFileURL.path)
        }
        return AppHealthSystemSnapshot(date: date, apps: apps,
                                       frontmost: workspace.frontmostApplication?.bundleIdentifier,
                                       idleSeconds: idleSeconds(), power: power, thermal: thermal,
                                       accessibilityTrusted: AXIsProcessTrusted())
    }

    /// Seconds since the last keyboard, mouse, or trackpad event of any kind in this login session.
    nonisolated static func idleSeconds() -> Int {
        // `~0` asks for any input event type (`kCGAnyInputEventType`).
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
        return seconds.isFinite ? max(0, Int(seconds)) : 0
    }

    /// The power source feeding the Mac now. `unknown` when IOKit reports no providing source.
    nonisolated static func powerSource() -> AppHealthPowerSource {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?
        else { return .unknown }
        switch type {
        case kIOPMACPowerKey: return .ac
        case kIOPMBatteryPowerKey: return .battery
        case kIOPMUPSPowerKey: return .ups
        default: return .unknown
        }
    }

    nonisolated static func thermalState() -> AppHealthThermalState {
        AppHealthThermalState(ProcessInfo.processInfo.thermalState)
    }
}
