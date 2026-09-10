import Foundation
import Observation

/// Playhead state for treating one dock's chrome as a time axis of ``DockLocalHistoryStore`` events.
///
/// Glance text follows the playhead immediately. Historical pin layout applies only after the
/// playhead stays on the same event for ``DockTimelinePinReplay/previewDwell``, and only when
/// replay is enabled. Preview never writes pins or records new history. DEE-45 can drive the
/// same progress value as audio-style playback without a second event log.
@MainActor @Observable
final class DockTimelineController {
    let history: DockLocalHistoryStore
    private(set) var isActive = false
    private(set) var displayID: String?
    private(set) var progress: Double = 1
    private(set) var replayPending = false
    private(set) var isReplayingPins = false
    /// Called once when an active session ends, so the coordinator can restore focus.
    @ObservationIgnored var onEnd: (() -> Void)?
    /// Applies a reconstructed pin list to one display. The store must not persist it.
    @ObservationIgnored var applyPreview: ((String, [DockPin]) -> Void)?
    /// Clears a display's timeline preview and restores saved pins.
    @ObservationIgnored var clearPreview: ((String) -> Void)?
    /// Injected so tests can settle without waiting the production dwell.
    @ObservationIgnored var previewDwell: Duration = DockTimelinePinReplay.previewDwell

    @ObservationIgnored private var dwellTask: Task<Void, Never>?
    @ObservationIgnored private var pendingEventID: UUID?
    @ObservationIgnored private var lastAppliedIDs: [String]?
    @ObservationIgnored private var layouts: [UUID: [String]] = [:]
    @ObservationIgnored private var pinLookup: [String: DockPin] = [:]
    @ObservationIgnored private var currentPins: [DockPin] = []

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
            replayEnabled: history.replayEnabled,
            replayPending: replayPending,
            isReplayingPins: isReplayingPins,
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
    func begin(on displayID: String, currentPins: [DockPin] = [], archive: [String: DockPin] = [:]) {
        self.displayID = displayID
        isActive = true
        progress = history.events.isEmpty ? 0 : 1
        self.currentPins = currentPins
        rebuildReplayCache(currentPins: currentPins, archive: archive)
        lastAppliedIDs = currentPins.map(\.id)
        replayPending = false
        isReplayingPins = false
        schedulePreviewIfNeeded()
    }

    func update(progress: Double) {
        guard isActive else { return }
        self.progress = min(1, max(0, progress.isFinite ? progress : 0))
        schedulePreviewIfNeeded()
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
        schedulePreviewIfNeeded()
    }

    func end() {
        let wasActive = isActive
        let endingDisplay = displayID
        cancelDwell()
        layouts = [:]
        pinLookup = [:]
        currentPins = []
        lastAppliedIDs = nil
        replayPending = false
        isReplayingPins = false
        isActive = false
        displayID = nil
        progress = 1
        if wasActive, let endingDisplay {
            clearPreview?(endingDisplay)
            onEnd?()
        }
    }

    /// Recomputes or drops preview after the Settings toggle changes while browsing.
    func replayPreferenceDidChange() {
        guard isActive else { return }
        if history.replayEnabled {
            rebuildReplayCache(currentPins: currentPins, archive: history.pinArchive)
            schedulePreviewIfNeeded()
            return
        }
        cancelDwell()
        replayPending = false
        if isReplayingPins, let displayID {
            isReplayingPins = false
            lastAppliedIDs = nil
            clearPreview?(displayID)
        }
    }

    /// True when this controller is browsing the given display's dock chrome.
    func isActive(on displayID: String) -> Bool {
        isActive && self.displayID == displayID
    }

    private func rebuildReplayCache(currentPins: [DockPin], archive: [String: DockPin]) {
        guard history.replayEnabled, let displayID else {
            layouts = [:]
            pinLookup = [:]
            return
        }
        layouts = DockTimelinePinReplay.layouts(
            events: history.events,
            currentIDs: currentPins.map(\.id),
            displayID: displayID
        )
        pinLookup = DockTimelinePinReplay.lookup(archive: archive, current: currentPins)
    }

    /// Applies pins only after the playhead stays on one event. Pointer motion on the same
    /// event does not restart the timer, so dragging does not thrash the dock.
    private func schedulePreviewIfNeeded() {
        guard isActive, history.replayEnabled, displayID != nil else {
            cancelDwell()
            replayPending = false
            if isReplayingPins {
                isReplayingPins = false
                lastAppliedIDs = nil
                if let displayID { clearPreview?(displayID) }
            }
            return
        }
        guard let event = selectedEvent, let ids = layouts[event.id] else {
            cancelDwell()
            replayPending = false
            return
        }
        if ids == lastAppliedIDs {
            cancelDwell()
            replayPending = false
            return
        }
        if pendingEventID == event.id { return }
        dwellTask?.cancel()
        pendingEventID = event.id
        replayPending = true
        let eventID = event.id
        let dwell = previewDwell
        dwellTask = Task { @concurrent in
            do {
                try await Task.sleep(for: dwell)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await applySettledPreview(eventID: eventID)
        }
    }

    private func applySettledPreview(eventID: UUID) {
        pendingEventID = nil
        guard isActive, history.replayEnabled, selectedEvent?.id == eventID,
              let displayID, let ids = layouts[eventID] else {
            replayPending = false
            return
        }
        guard ids != lastAppliedIDs else {
            replayPending = false
            return
        }
        applyPreview?(displayID, ids.compactMap { pinLookup[$0] })
        lastAppliedIDs = ids
        replayPending = false
        isReplayingPins = true
    }

    private func cancelDwell() {
        dwellTask?.cancel()
        dwellTask = nil
        pendingEventID = nil
    }
}

/// Snapshot the overlay can render without reaching into persistence.
struct DockTimelinePresentation: Equatable {
    var isActive: Bool
    var displayID: String?
    var isEmpty: Bool
    var recordingEnabled: Bool
    var replayEnabled: Bool = false
    var replayPending: Bool = false
    var isReplayingPins: Bool = false
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
