import Foundation

/// A single DDock-local history event.
///
/// Instantaneous by default. Session kinds may later carry a span via `endedAt` so
/// DEE-45 can treat a Focus Session as one scrubable clip without a second store.
/// Unknown future kinds decode as ``Kind/unrecognized(_:)`` so a newer writer cannot
/// lock an older reader out of the document.
nonisolated struct DockLocalHistoryEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let occurredAt: Date
    var endedAt: Date? = nil
    let kind: Kind
    var sessionID: UUID? = nil
    var displayID: String? = nil
    var subjectID: String? = nil
    var subjectName: String? = nil
    /// Pin identity order after this mutation, when known. Session events omit this and inherit
    /// the last snapshot for the same display while scrubbing.
    var pinIDs: [String]? = nil

    /// Pin mutations and Focus Session transitions recorded by DDock itself.
    ///
    /// New raw values must stay stable. DEE-45 may add playback markers; this slice
    /// must keep loading them as ``unrecognized(_:)`` rather than failing the document.
    enum Kind: Equatable, Hashable, Sendable {
        case pinAdded
        case pinRemoved
        case pinMoved
        case pinsReordered
        case sessionStarted
        case sessionPaused
        case sessionResumed
        case sessionFinished
        case sessionDismissed
        case unrecognized(String)

        var rawValue: String {
            switch self {
            case .pinAdded: "pinAdded"
            case .pinRemoved: "pinRemoved"
            case .pinMoved: "pinMoved"
            case .pinsReordered: "pinsReordered"
            case .sessionStarted: "sessionStarted"
            case .sessionPaused: "sessionPaused"
            case .sessionResumed: "sessionResumed"
            case .sessionFinished: "sessionFinished"
            case .sessionDismissed: "sessionDismissed"
            case .unrecognized(let value): value
            }
        }

        init(rawValue: String) {
            switch rawValue {
            case "pinAdded": self = .pinAdded
            case "pinRemoved": self = .pinRemoved
            case "pinMoved": self = .pinMoved
            case "pinsReordered": self = .pinsReordered
            case "sessionStarted": self = .sessionStarted
            case "sessionPaused": self = .sessionPaused
            case "sessionResumed": self = .sessionResumed
            case "sessionFinished": self = .sessionFinished
            case "sessionDismissed": self = .sessionDismissed
            default: self = .unrecognized(rawValue)
            }
        }

        var isPin: Bool {
            switch self {
            case .pinAdded, .pinRemoved, .pinMoved, .pinsReordered: true
            default: false
            }
        }

        var isSession: Bool {
            switch self {
            case .sessionStarted, .sessionPaused, .sessionResumed, .sessionFinished, .sessionDismissed: true
            default: false
            }
        }

        var isRecognized: Bool {
            if case .unrecognized = self { return false }
            return true
        }
    }

    var isPinEvent: Bool { kind.isPin }
    var isSessionEvent: Bool { kind.isSession }

    /// Glance title shown while scrubbing. App and folder names stay untranslated.
    var glanceTitle: LocalizedStringResource {
        let subject = String((subjectName ?? "").prefix(512))
        return switch kind {
        case .pinAdded: LocalizedStringResource.timelineEventPinAdded(subject: subject)
        case .pinRemoved: LocalizedStringResource.timelineEventPinRemoved(subject: subject)
        case .pinMoved: LocalizedStringResource.timelineEventPinMoved(subject: subject)
        case .pinsReordered: LocalizedStringResource.timelineEventPinsReordered
        case .sessionStarted: LocalizedStringResource.timelineEventSessionStarted(subject: subject)
        case .sessionPaused: LocalizedStringResource.timelineEventSessionPaused
        case .sessionResumed: LocalizedStringResource.timelineEventSessionResumed
        case .sessionFinished: LocalizedStringResource.timelineEventSessionFinished
        case .sessionDismissed: LocalizedStringResource.timelineEventSessionDismissed
        case .unrecognized: LocalizedStringResource.timelineEventUnrecognized
        }
    }

    var isValid: Bool {
        occurredAt.timeIntervalSince1970.isFinite
            && (endedAt?.timeIntervalSince1970.isFinite ?? true)
            && (endedAt.map { $0 >= occurredAt } ?? true)
            && (displayID?.count ?? 0) <= 256
            && (subjectID?.count ?? 0) <= 4096
            && (subjectName?.count ?? 0) <= 512
            && (kind.rawValue.count <= 128)
            && (pinIDs?.count ?? 0) <= DockLocalHistoryLimits.maximumPinsPerSnapshot
            && (pinIDs?.allSatisfy { !$0.isEmpty && $0.count <= 4096 } ?? true)
    }
}

extension DockLocalHistoryEvent.Kind: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self.init(rawValue: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Versioned local-only history. Nothing here is imported from Screen Time or other apps.
///
/// `replayEnabled` and `pinArchive` are optional on disk so documents written before pin
/// preview still load. Replay stays off unless the user turns it on.
nonisolated struct DockLocalHistoryDocument: Codable, Equatable, Sendable {
    var version = 1
    var recordingEnabled = true
    var replayEnabled = false
    var events: [DockLocalHistoryEvent] = []
    var pinArchive: [String: DockPin] = [:]

    enum CodingKeys: String, CodingKey {
        case version, recordingEnabled, replayEnabled, events, pinArchive
    }

    init(version: Int = 1, recordingEnabled: Bool = true, replayEnabled: Bool = false,
         events: [DockLocalHistoryEvent] = [], pinArchive: [String: DockPin] = [:]) {
        self.version = version
        self.recordingEnabled = recordingEnabled
        self.replayEnabled = replayEnabled
        self.events = events
        self.pinArchive = pinArchive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        recordingEnabled = try container.decodeIfPresent(Bool.self, forKey: .recordingEnabled) ?? true
        replayEnabled = try container.decodeIfPresent(Bool.self, forKey: .replayEnabled) ?? false
        events = try container.decodeIfPresent([DockLocalHistoryEvent].self, forKey: .events) ?? []
        pinArchive = try container.decodeIfPresent([String: DockPin].self, forKey: .pinArchive) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(recordingEnabled, forKey: .recordingEnabled)
        try container.encode(replayEnabled, forKey: .replayEnabled)
        try container.encode(events, forKey: .events)
        try container.encode(pinArchive, forKey: .pinArchive)
    }

    var isValid: Bool {
        version == 1
            && events.count <= DockLocalHistoryLimits.maximumEvents
            && events.allSatisfy(\.isValid)
            && pinArchive.count <= DockLocalHistoryLimits.maximumArchivedPins
            && pinArchive.keys.allSatisfy { !$0.isEmpty && $0.count <= 4096 }
    }
}

/// Shared bounds for the local history document. Keep writer and decoder in lockstep.
enum DockLocalHistoryLimits {
    static let maximumEvents = 500
    static let retention: TimeInterval = 90 * 86_400
    static let maximumEncodedBytes = 4_000_000
    static let maximumPinsPerSnapshot = 256
    static let maximumArchivedPins = 500
}

/// One user-facing pin edit inferred from two persisted lists.
///
/// Presentation-only writes (folder Grid/List/Smart, bookmark refresh) produce no mutations
/// when identity and order are unchanged. Mode activation never reaches this helper.
enum DockLocalHistoryPinMutation: Equatable, Sendable {
    case added(id: String, name: String)
    case removed(id: String, name: String)
    case moved(id: String, name: String)
    case reordered
}

enum DockLocalHistoryPinDiff {
    /// Compares persisted pin identity and order, not display-array position.
    static func mutations(previous: [DockPin], next: [DockPin]) -> [DockLocalHistoryPinMutation] {
        let previousIDs = previous.map(\.id)
        let nextIDs = next.map(\.id)
        guard previousIDs != nextIDs else { return [] }
        let previousSet = Set(previousIDs)
        let nextSet = Set(nextIDs)
        var mutations: [DockLocalHistoryPinMutation] = []
        for pin in next where !previousSet.contains(pin.id) {
            mutations.append(.added(id: pin.id, name: pin.name))
        }
        for pin in previous where !nextSet.contains(pin.id) {
            mutations.append(.removed(id: pin.id, name: pin.name))
        }
        if previousSet == nextSet {
            if let pin = relocatedPin(previous: previous, next: next) {
                mutations.append(.moved(id: pin.id, name: pin.name))
            } else {
                mutations.append(.reordered)
            }
        }
        return mutations
    }

    /// A single pin removed from one index and inserted at another, with the rest unmoved.
    static func relocatedPin(previous: [DockPin], next: [DockPin]) -> DockPin? {
        guard previous.count == next.count, previous.map(\.id) != next.map(\.id) else { return nil }
        for (index, pin) in previous.enumerated() {
            guard let destination = next.firstIndex(where: { $0.id == pin.id }), destination != index else { continue }
            var trial = previous
            trial.remove(at: index)
            trial.insert(pin, at: destination)
            if trial.map(\.id) == next.map(\.id) { return pin }
        }
        return nil
    }
}

/// Maps the dock's ordered axis onto local history time. Position 0 is the oldest event.
///
/// DEE-45 can reuse this for session playback: filter to one `sessionID`, then treat
/// progress as playhead. Events that share a timestamp fall back to stable index spacing
/// so each remains individually selectable.
enum DockTimelineMapping {
    static func progress(along position: CGFloat, length: CGFloat) -> Double {
        guard length > 0, position.isFinite, length.isFinite else { return 0 }
        return min(1, max(0, Double(position / length)))
    }

    static func eventIndex(at progress: Double, in events: [DockLocalHistoryEvent]) -> Int? {
        guard !events.isEmpty else { return nil }
        if events.count == 1 { return 0 }
        let clamped = min(1, max(0, progress.isFinite ? progress : 0))
        let start = events[0].occurredAt.timeIntervalSinceReferenceDate
        let end = events[events.count - 1].occurredAt.timeIntervalSinceReferenceDate
        if end <= start {
            return Int((clamped * Double(events.count - 1)).rounded())
        }
        let time = start + clamped * (end - start)
        return events.indices.min { lhs, rhs in
            abs(events[lhs].occurredAt.timeIntervalSinceReferenceDate - time)
                < abs(events[rhs].occurredAt.timeIntervalSinceReferenceDate - time)
        }
    }

    static func progress(for event: DockLocalHistoryEvent, in events: [DockLocalHistoryEvent]) -> Double {
        guard let first = events.first, let last = events.last else { return 0 }
        let start = first.occurredAt.timeIntervalSinceReferenceDate
        let end = last.occurredAt.timeIntervalSinceReferenceDate
        if end <= start {
            guard let index = events.firstIndex(where: { $0.id == event.id }) else { return 0 }
            return events.count == 1 ? 0 : Double(index) / Double(events.count - 1)
        }
        return min(1, max(0, (event.occurredAt.timeIntervalSinceReferenceDate - start) / (end - start)))
    }

    static func event(at progress: Double, in events: [DockLocalHistoryEvent]) -> DockLocalHistoryEvent? {
        guard let index = eventIndex(at: progress, in: events) else { return nil }
        return events[index]
    }
}
