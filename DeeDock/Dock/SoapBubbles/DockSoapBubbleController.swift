import Foundation
import Observation

/// Short-lived soap-bubble pops requested after an app click, pin, or drop.
///
/// Playback is gated here so views stay decorative. The saved preference can be on and
/// still produce no bursts when Reduce Motion is enabled. That preference is never rewritten.
@MainActor @Observable
final class DockSoapBubbleController {
    /// One burst anchored to a dock application identity.
    struct Burst: Identifiable, Equatable {
        let id: UUID
        let itemID: String
        let startedAt: Date
    }

    /// Hard cap so repeated clicks cannot accumulate layers on the dock surface.
    static let maximumConcurrentBursts = 3
    /// Matches the overlay's visual lifetime so removal does not cut a pop short.
    static let lifetime: TimeInterval = 0.55

    /// Saved preference copied from settings. Reduce Motion still suppresses `play`.
    var isEnabled = false
    private(set) var bursts: [Burst] = []

    @ObservationIgnored private var removalTasks: [UUID: Task<Void, Never>] = [:]

    /// Enqueues a burst when the preference is on and Reduce Motion is off.
    ///
    /// The call returns immediately. It never waits on animation or hit-testing.
    func play(itemID: String, reduceMotion: Bool) {
        guard isEnabled, !reduceMotion else { return }
        if bursts.count >= Self.maximumConcurrentBursts {
            finish(bursts[0].id)
        }
        let burst = Burst(id: UUID(), itemID: itemID, startedAt: .now)
        bursts.append(burst)
        removalTasks[burst.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.lifetime))
            guard !Task.isCancelled else { return }
            self?.finish(burst.id)
        }
    }

    /// Drops one burst and cancels its removal task.
    func finish(_ id: UUID) {
        removalTasks[id]?.cancel()
        removalTasks[id] = nil
        bursts.removeAll { $0.id == id }
    }

    /// Clears in-flight bursts when the preference turns off or Reduce Motion takes over.
    func removeAll() {
        removalTasks.values.forEach { $0.cancel() }
        removalTasks.removeAll()
        bursts.removeAll()
    }
}
