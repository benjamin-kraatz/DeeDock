import Foundation
import Observation

/// Playhead state for treating one dock's chrome as a time axis of ``DockLocalHistoryStore`` events.
///
/// v0 only browses. DEE-45 can drive the same progress value as audio-style playback
/// without a second event log.
@MainActor @Observable
final class DockTimelineController {
    let history: DockLocalHistoryStore
    private(set) var isActive = false
    private(set) var displayID: String?
    private(set) var progress: Double = 1
    /// Called once when an active session ends, so the coordinator can restore focus.
    @ObservationIgnored var onEnd: (() -> Void)?

    init(history: DockLocalHistoryStore) {
        self.history = history
    }

    var selectedEvent: DockLocalHistoryEvent? {
        DockTimelineMapping.event(at: progress, in: history.events)
    }

    var presentation: DockTimelinePresentation {
        let events = history.events
        return DockTimelinePresentation(
            isActive: isActive,
            displayID: displayID,
            isEmpty: events.isEmpty,
            recordingEnabled: history.recordingEnabled,
            progress: progress,
            selectedEvent: selectedEvent,
            markers: events.map { event in
                DockTimelineMarker(
                    id: event.id,
                    progress: DockTimelineMapping.progress(for: event, in: events),
                    kind: event.kind
                )
            }
        )
    }

    /// Starts browsing on one display's dock. Progress begins at the newest event.
    func begin(on displayID: String) {
        self.displayID = displayID
        isActive = true
        progress = history.events.isEmpty ? 0 : 1
    }

    func update(progress: Double) {
        guard isActive else { return }
        self.progress = min(1, max(0, progress.isFinite ? progress : 0))
    }

    /// Maps a point along the resting glass onto the time axis.
    func update(along position: CGFloat, length: CGFloat) {
        update(progress: DockTimelineMapping.progress(along: position, length: length))
    }

    /// Moves to the previous or next event. Used by Focus Dock arrows while the timeline is open.
    func nudge(by step: Int) {
        guard isActive, step != 0 else { return }
        let events = history.events
        guard !events.isEmpty else { return }
        let current = DockTimelineMapping.eventIndex(at: progress, in: events) ?? events.count - 1
        let next = min(events.count - 1, max(0, current + step))
        progress = DockTimelineMapping.progress(for: events[next], in: events)
    }

    func end() {
        let wasActive = isActive
        isActive = false
        displayID = nil
        progress = 1
        if wasActive { onEnd?() }
    }

    /// True when this controller is browsing the given display's dock chrome.
    func isActive(on displayID: String) -> Bool {
        isActive && self.displayID == displayID
    }
}

/// Snapshot the overlay can render without reaching into persistence.
struct DockTimelinePresentation: Equatable {
    var isActive: Bool
    var displayID: String?
    var isEmpty: Bool
    var recordingEnabled: Bool
    var progress: Double
    var selectedEvent: DockLocalHistoryEvent?
    var markers: [DockTimelineMarker]
}

/// One tick on the dock-axis track. Progress is 0...1 from oldest to newest.
struct DockTimelineMarker: Equatable, Identifiable {
    let id: UUID
    var progress: Double
    var kind: DockLocalHistoryEvent.Kind
}
