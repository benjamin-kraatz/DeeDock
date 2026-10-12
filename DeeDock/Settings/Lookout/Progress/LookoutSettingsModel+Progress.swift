import Foundation

/// The progress card's model and actions, on Lookout's Settings model.
extension LookoutSettingsModel {
    /// What the progress card shows; nil before setup, while Lookout is off, and while the model downloads (the
    /// status chip and onboarding cover the download). Previews can pin it.
    var progress: LookoutProgressDisplay? {
        previewProgress ?? LookoutProgressDisplay(status: status, index: engine.indexStatus)
    }

    /// "Pause": reading waits; what's indexed stays searchable.
    func pauseReading() {
        engine.pause()
    }

    /// "Resume" after "Pause".
    func resumeReading() {
        engine.resume()
    }
}

extension LookoutProgressDisplay {
    /// The display from the engine's status and the index service's last report. What the service doesn't report
    /// yet stays nil: the reading rate and the time left, when the last pass finished, and the reasons behind
    /// skipped and failed files. Pure, so the mapping is testable.
    ///
    /// - Returns: nil for statuses with nothing to track: not set up, off, or waiting for the model.
    nonisolated init?(status: LookoutStatus, index: LookoutIndexStatus?) {
        let counts = index?.counts
        let kinds = Self.kinds(from: counts)
        let total = counts?.files
        let done = total.map { max($0 - (counts?.pending ?? 0), 0) }
        let skipped = Self.total(counts, in: "skipped")
        let failed = Self.total(counts, in: "failed")

        switch status {
        case .notSetUp, .off, .waitingForModel:
            return nil

        case .indexing(let remaining, _):
            // The folders are still being walked until the service reports anything, and while it syncs with no
            // files counted yet. A sync with files already known is a later pass: its total may still grow, but
            // the ring can show how far the known files are.
            let syncing = index?.activity == .syncing
            let counting = index == nil || (syncing && (total ?? 0) == 0)
            self.init(phase: counting ? .counting : .reading, done: done ?? 0, total: total,
                      totalIsFinal: !syncing && index != nil, remaining: remaining, kinds: kinds,
                      skipped: skipped, failed: failed)

        case .ready:
            self.init(phase: .upToDate, done: done ?? 0, total: total, totalIsFinal: true, remaining: 0,
                      kinds: kinds, skipped: skipped, failed: failed)

        case .paused(let reason):
            self.init(phase: .paused(reason: PauseReason(reason)), done: done ?? 0, total: total,
                      totalIsFinal: index?.activity != .syncing, remaining: counts.map { $0.pending + $0.unfinished },
                      kinds: kinds, skipped: skipped, failed: failed)

        case .failed(let failure):
            self.init(phase: .failed(message: failure.message), done: done ?? 0, total: total,
                      totalIsFinal: true, remaining: counts?.pending, kinds: kinds, skipped: skipped,
                      failed: failed)
        }
    }

    /// Each kind's files no longer waiting out of all of that kind, from the service's `byKindAndState`.
    private nonisolated static func kinds(from counts: IndexStore.Counts?) -> [FileKind: KindProgress] {
        guard let counts else { return [:] }
        var kinds: [FileKind: KindProgress] = [:]
        for (raw, states) in counts.byKindAndState {
            guard let kind = FileKind(rawValue: raw) else { continue }
            let total = states.values.reduce(0, +)
            let pending = states["pending"] ?? 0
            kinds[kind] = KindProgress(done: max(total - pending, 0), total: total)
        }
        return kinds
    }

    private nonisolated static func total(_ counts: IndexStore.Counts?, in state: String) -> Int {
        counts?.byKindAndState.values.reduce(0) { $0 + ($1[state] ?? 0) } ?? 0
    }
}

extension LookoutProgressDisplay.PauseReason {
    /// The display's reason for the engine's.
    nonisolated init(_ reason: LookoutPauseReason) {
        switch reason {
        case .lowPowerMode: self = .lowPowerMode
        case .warm: self = .thermal
        case .onBattery: self = .onBattery
        case .user: self = .userPaused
        }
    }
}
