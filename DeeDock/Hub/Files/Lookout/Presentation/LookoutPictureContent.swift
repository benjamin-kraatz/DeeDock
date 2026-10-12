import Foundation

/// What the results of a search with a picture show under the results bar, for a status, a phase and results (the
/// mockup's `renderImgBody`). Pure, so every combination is testable without a view.
nonisolated struct LookoutPictureContent: Equatable, Sendable {
    /// A line above the results about what may be missing.
    enum Notice: Equatable, Sendable {
        /// Still reading files (the text search's note); `remaining` when known.
        case indexing(remaining: Int?)
        /// Reading files waits, but the picture is still read and searched with.
        case paused(LookoutPauseReason)
        case failed(LookoutFailure)
    }

    enum Body: Equatable, Sendable {
        /// Not set up: "Search with a picture" and Set up Lookout.
        case promo
        /// The model is downloading: the download card, about the Pictures model.
        case download
        /// The picture is on its way: three shimmer rows.
        case skeleton
        /// The picture couldn't be read or encoded.
        case unreadable
        /// Nothing stands out in either group.
        case honest
        /// The two groups.
        case groups
        /// Nothing (Lookout was turned off).
        case nothing
    }

    let notice: Notice?
    let body: Body

    init(status: LookoutStatus, phase: LookoutPictureSearch.Phase, results: LookoutSimilarResults) {
        switch status {
        case .notSetUp:
            (notice, body) = (nil, .promo)
            return
        case .off:
            (notice, body) = (nil, .nothing)
            return
        case .waitingForModel:
            (notice, body) = (nil, .download)
            return
        case .indexing(let remaining, _): notice = .indexing(remaining: remaining)
        case .paused(let reason): notice = .paused(reason)
        case .failed(let failure): notice = .failed(failure)
        case .ready: notice = nil
        }
        switch phase {
        case .idle, .lookingUp, .waking, .reading: body = .skeleton
        case .failed: body = .unreadable
        case .unavailable: body = .honest
        case .done: body = results.hasNoStrongHits ? .honest : .groups
        }
    }

    /// Whether Lookout can search at all in this status (the results bar then says how the picture was read).
    static func canSearch(_ status: LookoutStatus) -> Bool {
        switch status {
        case .notSetUp, .off, .waitingForModel: false
        case .indexing, .ready, .paused, .failed: true
        }
    }
}
