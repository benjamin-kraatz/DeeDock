extension AnalyticsUninstallOutcome {
    /// The outcome of a sheet that closed after removal stopped for `stop`.
    init(_ stop: AppUninstallSession.Stop) {
        switch stop {
        case .passwordCancelled: self = .passwordCancelled
        case .stillOpen: self = .stillOpen
        case .failed: self = .failed
        }
    }
}

extension AnalyticsUninstallSource {
    /// The token for `source`; `.unknown` until inspection finished.
    init(_ source: AppUninstallSource?) {
        switch source {
        case .appStore: self = .appStore
        case .testFlight: self = .testFlight
        case .installer: self = .installer
        case .downloaded: self = .downloaded
        case nil: self = .unknown
        }
    }
}
