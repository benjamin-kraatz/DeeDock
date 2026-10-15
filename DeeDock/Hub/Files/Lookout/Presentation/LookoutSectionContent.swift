import Foundation

/// What the Lookout section shows under its header for a status, a search phase and results. Pure, so every
/// combination is testable without a view.
nonisolated struct LookoutSectionContent: Equatable, Sendable {
    /// A line above the results about what may be missing.
    enum Notice: Equatable, Sendable {
        /// Still reading files; `remaining` when known.
        case indexing(remaining: Int?)
        case paused(LookoutPauseReason)
        case failed(LookoutFailure)
    }

    enum Body: Equatable, Sendable {
        /// Not set up: the promo card.
        case promo
        /// The model is downloading: the download card.
        case download
        /// Nothing has arrived yet: three shimmer rows.
        case skeleton
        /// Hits to list (keyword-only ones first, then the final ones).
        case results
        /// The final results are empty: the honest empty state.
        case empty
        /// Nothing below the header or the notice (Lookout is off, or can't search yet).
        case nothing
    }

    let notice: Notice?
    let body: Body

    init(status: LookoutStatus, phase: LookoutSearch.Phase, results: LookoutResultSet) {
        switch status {
        case .notSetUp:
            notice = nil
            body = .promo
            return
        case .off:
            // Turned off on purpose: the results hide the section (`HubFilesModel.showsLookoutSection`).
            notice = nil
            body = .nothing
            return
        case .waitingForModel:
            notice = nil
            body = .download
            return
        case .indexing(let remaining, _): notice = .indexing(remaining: remaining)
        case .paused(let reason): notice = .paused(reason)
        case .failed(let failure): notice = .failed(failure)
        case .ready: notice = nil
        }
        if !results.isEmpty {
            body = .results
        } else {
            switch phase {
            case .done: body = .empty
            case .idle, .warming, .keywordOnly: body = .skeleton
            // No index yet (or none readable): a ready Lookout says it found nothing; otherwise the notice explains.
            case .unavailable: body = notice == nil ? .empty : .nothing
            }
        }
    }
}
