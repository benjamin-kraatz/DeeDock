import Foundation

/// Reconstructs a display's pin identity order at a local-history event.
///
/// New pin events store `pinIDs` after the mutation. Older events without snapshots
/// invert later add/remove events from the live list. Move and reorder without
/// snapshots keep the current order rather than guessing. Preview must resolve IDs
/// through ``lookup(archive:current:)`` and must never persist the result.
nonisolated enum DockTimelinePinReplay {
    /// Time the playhead must stay on one event before pin layout changes.
    ///
    /// Glance and playhead updates stay immediate. Waiting avoids swapping the dock
    /// on every pointer sample while the user is still dragging.
    static let previewDwell: Duration = .milliseconds(200)

    /// Pin identity order at every event, keyed by event id, for one display.
    static func layouts(events: [DockLocalHistoryEvent], currentIDs: [String],
                        displayID: String) -> [UUID: [String]] {
        Dictionary(uniqueKeysWithValues: events.indices.map { index in
            (events[index].id, pinIDs(at: index, events: events, currentIDs: currentIDs, displayID: displayID))
        })
    }

    /// Pin identity order after `events[index]` as it applied to `displayID`.
    ///
    /// Uses the newest snapshot for that display at or before the index. When none
    /// exists, walks later pin events for the same display backward from `currentIDs`.
    static func pinIDs(at index: Int, events: [DockLocalHistoryEvent], currentIDs: [String],
                       displayID: String) -> [String] {
        guard events.indices.contains(index) else { return currentIDs }
        if let snapshot = events[...index].last(where: {
            $0.pinIDs != nil && $0.displayID == displayID
        })?.pinIDs {
            return snapshot
        }
        var ids = currentIDs
        for event in events[(index + 1)...].reversed() where event.displayID == displayID && event.isPinEvent {
            ids = invert(event, on: ids)
        }
        return ids
    }

    /// Resolves archived and live pins so a reconstructed id list can become ``DockPin`` values.
    ///
    /// Live pins win when the same id exists in both, so names and bookmarks stay current.
    static func lookup(archive: [String: DockPin], current: [DockPin]) -> [String: DockPin] {
        var pins = archive
        for pin in current { pins[pin.id] = pin }
        return pins
    }

    /// Applies the inverse of one recorded pin mutation. Unknown or session kinds are ignored.
    static func invert(_ event: DockLocalHistoryEvent, on ids: [String]) -> [String] {
        switch event.kind {
        case .pinAdded:
            guard let subject = event.subjectID else { return ids }
            return ids.filter { $0 != subject }
        case .pinRemoved:
            guard let subject = event.subjectID, !ids.contains(subject) else { return ids }
            var next = ids
            next.append(subject)
            return next
        default:
            return ids
        }
    }
}
