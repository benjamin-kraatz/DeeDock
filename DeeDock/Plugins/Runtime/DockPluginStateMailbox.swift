import Foundation
import os

/// Holds the latest tile state a plugin sent until the main actor takes it.
///
/// A plugin is a third-party process and can push states faster than the main actor applies
/// them. Instead of one main-actor task per message, the connection keeps only the newest
/// undelivered state and schedules at most one delivery at a time; older states that were never
/// shown are replaced. Thread-safe: XPC calls ``put(_:)`` on its own queue.
nonisolated final class DockPluginStateMailbox: Sendable {
    private struct Contents {
        var state: DOKKPluginTileState?
        var deliveryScheduled = false
    }

    private let contents = OSAllocatedUnfairLock(initialState: Contents())

    /// Stores `state`, replacing any state not yet taken.
    /// - Returns: True when the caller must schedule a delivery; false when one is already pending
    ///   and will pick this state up.
    func put(_ state: DOKKPluginTileState) -> Bool {
        contents.withLock { contents in
            contents.state = state
            guard !contents.deliveryScheduled else { return false }
            contents.deliveryScheduled = true
            return true
        }
    }

    /// Takes the latest state and lets the next ``put(_:)`` schedule a new delivery.
    func take() -> DOKKPluginTileState? {
        contents.withLock { contents in
            defer { contents = Contents() }
            return contents.state
        }
    }
}
