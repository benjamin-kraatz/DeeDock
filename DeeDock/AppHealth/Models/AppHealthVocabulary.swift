import Foundation

// The closed vocabularies App Health writes into its records. Raw values are the schema: they appear verbatim in
// the JSON Lines files and in `docs/APP-HEALTH.md`, so renaming a case is a schema change.

/// How macOS lets an app present itself, from `NSRunningApplication.activationPolicy`.
nonisolated enum AppHealthAppKind: String, Codable, Sendable, CaseIterable {
    /// A Dock app with a menu bar (`.regular`).
    case regular
    /// A menu-bar or agent app (`.accessory`).
    case accessory
    /// A faceless app (`.prohibited`).
    case background
}

/// The power source feeding the Mac, from `IOPSGetProvidingPowerSourceType`.
nonisolated enum AppHealthPowerSource: String, Codable, Sendable, CaseIterable {
    case ac, battery, ups, unknown
}

/// `ProcessInfo.ThermalState`, as written to disk.
nonisolated enum AppHealthThermalState: String, Codable, Sendable, CaseIterable {
    case nominal, fair, serious, critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }
}

/// The outcome of one responsiveness check through Accessibility.
nonisolated enum AppHealthHangResult: String, Codable, Sendable, CaseIterable {
    /// The app answered within the timeout.
    case ok
    /// The app did not answer within the timeout (`kAXErrorCannotComplete`).
    case timeout
    /// Any other Accessibility failure, such as an app that exposes no Accessibility tree.
    case error
}

/// Which processes carried an app's CPU time during one tick.
nonisolated enum AppHealthLoad: String, Codable, Sendable, CaseIterable {
    /// The main process used at least as much CPU as the helpers together.
    case main
    /// Helpers used more CPU than the main process.
    case helpers
    /// No CPU time at all.
    case none

    init(cpuMain: Double, cpuHelpers: Double) {
        if cpuMain + cpuHelpers <= 0 { self = .none }
        else if cpuHelpers > cpuMain { self = .helpers }
        else { self = .main }
    }
}

/// Why a `sample` row was written. Every app is sampled every tick; only these rows reach disk.
nonisolated enum AppHealthWriteReason: String, Codable, Sendable, CaseIterable {
    /// The app was busy this tick, or within the hysteresis tail after it was.
    case active
    /// The periodic row that keeps a quiet app's series anchored.
    case baseline
    /// The memory footprint moved far enough since the last written row.
    case growth
    /// A prompt or manual label asked for the whole labelled window.
    case backfill
}

/// The `event` record's `event` field.
nonisolated enum AppHealthEventKind: String, Codable, Sendable, CaseIterable {
    case launched, terminated
    case sleep, wake, displaySleep, displayWake, sessionInactive, sessionActive
    case power, thermal
    case collectorStart, collectorStop
    case dontAsk, allowAsk, pauseToday, resume
}

/// Why sampling started or stopped, carried by `collectorStart` and `collectorStop` events.
nonisolated enum AppHealthCollectorReason: String, Codable, Sendable, CaseIterable {
    /// The person turned collection on, or DOKK launched with it on.
    case enabled
    /// The person turned collection off.
    case disabled
    /// The Mac went to sleep, or woke from it.
    case sleep
    /// The displays went to sleep, or woke.
    case displaySleep
    /// The login session became inactive (fast user switching), or active again.
    case session
    /// DOKK quit.
    case quit
}

/// What led to a labelling prompt.
nonisolated enum AppHealthPromptTrigger: String, Codable, Sendable, CaseIterable {
    /// The suspicion rule held.
    case rule
    /// Ordinary heavy use, sampled so the data also contains legitimately busy apps.
    case ordinary
    /// The person picked the app from "Something's off right now…".
    case manual
}

/// One flag of the suspicion rule that held when a prompt was shown.
nonisolated enum AppHealthPromptReason: String, Codable, Sendable, CaseIterable {
    case cpu, background, idleUser, memory, wakeups, hang
}

/// Where a prompt panel was attached.
nonisolated enum AppHealthAnchorKind: String, Codable, Sendable, CaseIterable {
    /// The app's own tile on a dock that is shown.
    case tile
    /// The centre of the primary display's dock, because the app has no visible tile.
    case dock
    /// The lower-right corner of the main screen, because no dock is shown.
    case screen
}

/// The person's answer to "Is <App> behaving as expected?".
nonisolated enum AppHealthAnswer: String, Codable, Sendable, CaseIterable {
    case expected, misbehaving, notSure, noAnswer
}

/// The optional follow-up after "Misbehaving".
nonisolated enum AppHealthAnswerDetail: String, Codable, Sendable, CaseIterable {
    case spinning, memoryGrowing, frozen, drainingBattery
}

/// Where a label came from.
nonisolated enum AppHealthLabelSource: String, Codable, Sendable, CaseIterable {
    case prompt, manual
}
