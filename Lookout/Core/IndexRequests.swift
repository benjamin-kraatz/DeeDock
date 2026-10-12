/// The index service's requests that wait for its work queue, and what one pass takes of them (`IndexWork`, which
/// guards this with its lock).
///
/// A request stays until a pass performs it. A pass while paused, or while no app is connected, only applies a new
/// configuration (the index opens and prunes at once). The sync and the reset it can't do stay waiting, and so does
/// the sync a new configuration asks for. Resuming also asks for a sync, so reading starts from a fresh crawl whatever
/// changed while it was paused. Without this, a sync or "Read everything again" that arrived while paused was dropped,
/// and a resume within the service's idle minute never crawled.
///
/// It lives in `Core`, not beside `IndexWork`, so the app's tests can reach it.
nonisolated struct IndexRequests: Sendable {
    /// A configuration not applied yet.
    var configuration: LookoutIndexConfiguration?
    var sync = false
    /// "Read everything again": the next pass that may work resets the index before it syncs.
    var reset = false
    var paused = false
    /// No app is connected.
    var appAway = false

    /// What a pass does.
    struct Pass: Sendable {
        var configuration: LookoutIndexConfiguration?
        var sync = false
        var reset = false
        /// Paused, or no app: apply `configuration`, then settle without reading.
        var isHeld = false
        var paused = false
    }

    /// Takes what a pass does now and leaves the rest waiting.
    mutating func take() -> Pass {
        var pass = Pass(configuration: configuration, isHeld: paused || appAway, paused: paused)
        configuration = nil
        if pass.isHeld {
            // The new configuration's own sync waits for the resume with the others.
            if pass.configuration != nil { sync = true }
            return pass
        }
        (pass.sync, pass.reset) = (sync, reset)
        (sync, reset) = (false, false)
        return pass
    }

    /// Reading may go on: crawl first, because the folders may have changed meanwhile.
    mutating func resume() {
        paused = false
        sync = true
    }

    /// The app is closing the index: what it asked for before no longer applies.
    mutating func dropWork() {
        configuration = nil
        (sync, reset) = (false, false)
    }
}
