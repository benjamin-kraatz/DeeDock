import Foundation

/// The status chip's words for each status. Phase 2's chip and phase 3's Settings show these; nothing else should
/// spell a status out.
nonisolated extension LookoutStatus {
    /// The short label: "Lookout ready", "Reading files", "Paused".
    var title: LocalizedStringResource {
        switch self {
        case .notSetUp: .lookoutStatusNotSetUp
        case .off: .lookoutStatusOff
        case .waitingForModel: .lookoutStatusWaitingForModel
        case .indexing(let remaining, _): remaining == nil ? .lookoutStatusPreparing : .lookoutStatusIndexing
        case .ready: .lookoutStatusReady
        case .paused: .lookoutStatusPaused
        case .failed: .lookoutStatusFailed
        }
    }

    /// A second line, when there is one: files left, why reading waits, what failed.
    var detail: String? {
        switch self {
        case .indexing(let remaining?, _) where remaining > 0:
            String(localized: .lookoutStatusIndexingRemaining(remaining))
        case .paused(let reason):
            String(localized: reason.title)
        case .failed(let failure):
            failure.message
        default:
            nil
        }
    }
}

nonisolated extension LookoutPauseReason {
    /// Why reading waits, in a few words.
    var title: LocalizedStringResource {
        switch self {
        case .lowPowerMode: .lookoutPauseLowPowerMode
        case .warm: .lookoutPauseWarm
        case .onBattery: .lookoutPauseOnBattery
        case .user: .lookoutPauseUser
        }
    }
}
