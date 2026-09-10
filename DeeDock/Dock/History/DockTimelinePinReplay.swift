import Foundation

/// Reconstructs pin identity order at a local-history event.
///
/// An event's own `pinIDs` always win. Older events without snapshots invert later
/// add/remove mutations from the live list, then fall back to a forward walk from the
/// recorded adds and removes. Preview must resolve IDs through ``lookup(archive:current:)``
/// and must never persist the result.
nonisolated enum DockTimelinePinReplay {
    /// Time the playhead must stay on one event before pointer-driven pin layout changes.
    static let previewDwell: Duration = .milliseconds(200)

    /// Pin identity order at every event, keyed by event id.
    static func layouts(events: [DockLocalHistoryEvent], currentIDs: [String],
                        displayID: String) -> [UUID: [String]] {
        Dictionary(uniqueKeysWithValues: events.indices.map { index in
            (events[index].id, pinIDs(at: index, events: events, currentIDs: currentIDs, displayID: displayID))
        })
    }

    /// Pin identity order after `events[index]`.
    ///
    /// The selected event's snapshot is used even when it was recorded on another display,
    /// so the dock follows the glance entry. Session events inherit the last snapshot.
    static func pinIDs(at index: Int, events: [DockLocalHistoryEvent], currentIDs: [String],
                       displayID: String) -> [String] {
        guard events.indices.contains(index) else { return currentIDs }
        if let own = events[index].pinIDs { return own }
        if let snapshot = events[...index].last(where: {
            $0.pinIDs != nil && ($0.displayID == displayID || $0.displayID == nil)
        })?.pinIDs {
            return snapshot
        }
        if let snapshot = events[...index].last(where: { $0.pinIDs != nil })?.pinIDs {
            return snapshot
        }
        var inverted = currentIDs
        for event in events[(index + 1)...].reversed() where event.isPinEvent {
            inverted = invert(event, on: inverted)
        }
        if inverted != currentIDs { return inverted }
        let forward = forwardIDs(through: index, events: events)
        return forward.isEmpty ? currentIDs : forward
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

    /// Rebuilds a list from add/remove events only, used when no snapshot exists and invert
    /// cannot distinguish the target moment from the live dock.
    static func forwardIDs(through index: Int, events: [DockLocalHistoryEvent]) -> [String] {
        guard events.indices.contains(index) else { return [] }
        var ids: [String] = []
        for event in events[...index] where event.isPinEvent {
            ids = apply(event, on: ids)
        }
        return ids
    }

    static func apply(_ event: DockLocalHistoryEvent, on ids: [String]) -> [String] {
        switch event.kind {
        case .pinAdded:
            guard let subject = event.subjectID, !ids.contains(subject) else { return ids }
            var next = ids
            next.append(subject)
            return next
        case .pinRemoved:
            guard let subject = event.subjectID else { return ids }
            return ids.filter { $0 != subject }
        default:
            return ids
        }
    }
}
