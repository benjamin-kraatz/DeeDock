import AppKit

/// One running app App Health watches this tick.
///
/// `bundlePath` and the executable name live only in memory: the sampler uses the path to attribute embedded
/// helpers, and the crash-report lookup matches the executable name. Neither is ever written or logged.
nonisolated struct AppHealthWatchedApp: Sendable, Equatable {
    let bundleID: String
    let kind: AppHealthAppKind
    let pid: pid_t
    /// The app bundle's file-system path, for helper attribution only.
    let bundlePath: String?
}

/// An app that just launched or terminated, as the workspace notification described it.
nonisolated struct AppHealthAppIdentity: Sendable, Equatable {
    let bundleID: String
    let kind: AppHealthAppKind
    let pid: pid_t
    /// The executable's file name, for the crash-report lookup only. Never written.
    let executableName: String?
    let launchDate: Date?
}

/// Everything the main actor gathers cheaply at the start of a tick, before the sampler runs.
nonisolated struct AppHealthSystemSnapshot: Sendable {
    let date: Date
    let apps: [AppHealthWatchedApp]
    /// The frontmost app's bundle identifier.
    let frontmost: String?
    /// Whole seconds since the last input event in this login session.
    let idleSeconds: Int
    let power: AppHealthPowerSource
    let thermal: AppHealthThermalState
    /// `AXIsProcessTrusted()`: Accessibility was already allowed, so responsiveness checks may run.
    let accessibilityTrusted: Bool
}

extension AppHealthAppKind {
    init(_ policy: NSApplication.ActivationPolicy) {
        switch policy {
        case .regular: self = .regular
        case .accessory: self = .accessory
        case .prohibited: self = .background
        @unknown default: self = .background
        }
    }
}

extension AppHealthAppIdentity {
    /// Nil for a process without a bundle identifier, which App Health does not watch.
    @MainActor init?(_ application: NSRunningApplication) {
        guard let bundleID = application.bundleIdentifier else { return nil }
        self.init(bundleID: bundleID, kind: AppHealthAppKind(application.activationPolicy),
                  pid: application.processIdentifier,
                  executableName: application.executableURL?.lastPathComponent,
                  launchDate: application.launchDate)
    }
}
