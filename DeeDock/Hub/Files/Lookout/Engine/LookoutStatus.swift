import Foundation

/// What Lookout is doing, as the UI shows it (the status chip, Settings). `LookoutEngine.status` publishes it;
/// `LookoutStatus.map` derives it.
nonisolated enum LookoutStatus: Equatable, Sendable {
    /// Onboarding hasn't completed setup.
    case notSetUp
    /// Set up, then turned off.
    case off
    /// The model files aren't all there yet; file names are indexed meanwhile.
    case waitingForModel
    /// Syncing or reading files. `remaining` is how many files still wait (nil before the first status arrives);
    /// `progress` is 0…1 through the current pass, when the service knows its size.
    case indexing(remaining: Int?, progress: Double?)
    /// Everything that may be read is read.
    case ready
    /// Reading waits; what's indexed stays searchable.
    case paused(LookoutPauseReason)
    case failed(LookoutFailure)
}

/// Why reading waits.
nonisolated enum LookoutPauseReason: String, Equatable, Sendable {
    case lowPowerMode
    /// Thermal state serious or critical.
    case warm
    /// On battery with "Read files on battery too" off.
    case onBattery
    /// The person paused it.
    case user

    init(_ blocker: LookoutBackfillBlocker) {
        switch blocker {
        case .lowPowerMode: self = .lowPowerMode
        case .warm: self = .warm
        case .onBattery: self = .onBattery
        }
    }
}

/// Why Lookout stopped. `message` is the localized explanation; `detail` is the service's own words, unlocalized,
/// for logs and diagnostics only (it may name a file and must never reach analytics).
nonisolated struct LookoutFailure: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        /// The index can't be opened or created.
        case index
        /// Syncing or reading failed (the model can't load, the index can't be written).
        case indexing
        /// The index service can't be reached.
        case service
    }

    let kind: Kind
    let detail: String?

    /// The localized explanation.
    var message: String {
        switch kind {
        case .index: String(localized: .lookoutFailedIndex)
        case .indexing: String(localized: .lookoutFailedIndexing)
        case .service: String(localized: .lookoutFailedService)
        }
    }

    /// Sorts a service failure message (`LookoutIndexStatus.Activity.failed`) into a kind.
    init(serviceMessage: String) {
        kind = serviceMessage.hasPrefix("can't open the index") ? .index : .indexing
        detail = serviceMessage
    }

    init(kind: Kind, detail: String? = nil) {
        self.kind = kind
        self.detail = detail
    }
}

nonisolated extension LookoutStatus {
    /// The UI status from everything the engine knows. Pure, so every combination is testable.
    ///
    /// - Parameters:
    ///   - settings: The current settings.
    ///   - index: The index service's latest status; nil before the first one arrives.
    ///   - blocker: The power policy's verdict.
    ///   - userPaused: The person paused reading.
    ///   - serviceUnavailable: The index service can't be reached.
    static func map(settings: LookoutSettings, index: LookoutIndexStatus?, blocker: LookoutBackfillBlocker?,
                    userPaused: Bool, serviceUnavailable: Bool) -> LookoutStatus {
        guard settings.setupCompleted else { return .notSetUp }
        guard settings.enabled else { return .off }
        if userPaused { return .paused(.user) }
        if serviceUnavailable { return .failed(LookoutFailure(kind: .service)) }
        guard let index else { return .indexing(remaining: nil, progress: nil) }
        let counts = index.counts
        let progress = index.total > 0 ? min(max(Double(index.done) / Double(index.total), 0), 1) : nil
        switch index.activity {
        case .failed(let message):
            return .failed(LookoutFailure(serviceMessage: message))
        case .waitingForModel:
            return .waitingForModel
        case .paused:
            return .paused(.user)
        case .syncing:
            return .indexing(remaining: counts.pending, progress: nil)
        case .indexing:
            // A blocked backfill still reads up to 50 new files first; that is indexing too.
            return .indexing(remaining: counts.pending, progress: progress)
        case .finishingLongFiles:
            return .indexing(remaining: counts.unfinished, progress: progress)
        case .idle:
            // Idle with files waiting means the backfill isn't allowed: say why.
            if counts.pending + counts.unfinished > 0, let blocker { return .paused(LookoutPauseReason(blocker)) }
            return .ready
        }
    }
}
