import Foundation

/// The `tick` record: one per written tick, describing the context every `sample` row of that tick shares.
nonisolated struct AppHealthTickRecord: Codable, Sendable, Equatable {
    /// Seconds actually elapsed since the previous tick.
    var interval: Double
    /// The frontmost app's bundle identifier, omitted when no app with one is frontmost.
    var frontmost: String?
    /// Whole seconds since the last keyboard, mouse, or trackpad input in this login session.
    var idle: Int
    var power: AppHealthPowerSource
    var thermal: AppHealthThermalState
    /// How many apps were watched this tick.
    var apps: Int
    /// How many `sample` rows this tick wrote.
    var written: Int
    /// Thread CPU time the sampler spent in libproc this tick, in milliseconds.
    var costMs: Double
    /// Whether Accessibility was already allowed, so responsiveness checks ran.
    var ax: Bool

    init(interval: Double, frontmost: String?, idle: Int, power: AppHealthPowerSource,
         thermal: AppHealthThermalState, apps: Int, written: Int, costMs: Double, ax: Bool) {
        self.interval = AppHealthRounding.seconds(interval)
        self.frontmost = frontmost
        self.idle = idle
        self.power = power
        self.thermal = thermal
        self.apps = apps
        self.written = written
        self.costMs = AppHealthRounding.seconds(costMs)
        self.ax = ax
    }
}

/// The `sample` record: one app's resource use over one tick. Built from an `AppHealthSample`, rounded.
nonisolated struct AppHealthSampleRecord: Codable, Sendable, Equatable {
    var app: String
    var kind: AppHealthAppKind
    var interval: Double
    var cpu: Double
    var cpuMain: Double
    var cpuHelpers: Double
    var cpuPct: Double
    var mem: UInt64
    var memMain: UInt64
    var procs: Int
    var wakeups: UInt64
    var wakeupsPerSec: Double
    var energy: UInt64?
    var load: AppHealthLoad
    var frontmost: Bool
    var hang: AppHealthHangResult?
    var hangMs: Int?
    var why: AppHealthWriteReason

    init(_ sample: AppHealthSample, why: AppHealthWriteReason) {
        app = sample.app
        kind = sample.kind
        interval = AppHealthRounding.seconds(sample.interval)
        cpu = AppHealthRounding.seconds(sample.cpu)
        cpuMain = AppHealthRounding.seconds(sample.cpuMain)
        cpuHelpers = AppHealthRounding.seconds(sample.cpuHelpers)
        cpuPct = AppHealthRounding.tenths(sample.cpuPercent)
        mem = sample.mem
        memMain = sample.memMain
        procs = sample.procs
        wakeups = sample.wakeups
        wakeupsPerSec = AppHealthRounding.tenths(sample.wakeupsPerSecond)
        energy = sample.energy
        load = sample.load
        frontmost = sample.frontmost
        hang = sample.hang
        hangMs = sample.hangMs
        self.why = why
    }
}

/// The `event` record. Which optional fields are present depends on `event`; absent fields are omitted.
nonisolated struct AppHealthEventRecord: Codable, Sendable, Equatable {
    var event: AppHealthEventKind
    var app: String?
    var kind: AppHealthAppKind?
    /// Whole seconds between launch and termination, when macOS reported a launch date.
    var runSeconds: Int?
    /// Mean CPU of at least 50 % over the last two minutes of in-memory history before termination.
    var heavyBefore: Bool?
    /// The app's last responsiveness check before termination timed out.
    var hangFailing: Bool?
    /// The app was frontmost in at least one tick of the last two minutes before termination.
    var frontmostRecently: Bool?
    /// A crash report for the app appeared around the termination. Omitted when the lookup could not finish.
    var crashReport: Bool?
    var power: AppHealthPowerSource?
    var thermal: AppHealthThermalState?
    var reason: AppHealthCollectorReason?

    init(event: AppHealthEventKind, app: String? = nil, kind: AppHealthAppKind? = nil, runSeconds: Int? = nil,
         heavyBefore: Bool? = nil, hangFailing: Bool? = nil, frontmostRecently: Bool? = nil,
         crashReport: Bool? = nil, power: AppHealthPowerSource? = nil, thermal: AppHealthThermalState? = nil,
         reason: AppHealthCollectorReason? = nil) {
        self.event = event
        self.app = app
        self.kind = kind
        self.runSeconds = runSeconds
        self.heavyBefore = heavyBefore
        self.hangFailing = hangFailing
        self.frontmostRecently = frontmostRecently
        self.crashReport = crashReport
        self.power = power
        self.thermal = thermal
        self.reason = reason
    }

    static func collector(_ event: AppHealthEventKind, reason: AppHealthCollectorReason) -> Self {
        Self(event: event, reason: reason)
    }

    static func app(_ event: AppHealthEventKind, _ app: String, kind: AppHealthAppKind? = nil) -> Self {
        Self(event: event, app: app, kind: kind)
    }
}
