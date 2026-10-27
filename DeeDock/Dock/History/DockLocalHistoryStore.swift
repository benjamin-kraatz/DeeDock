import Foundation
import Observation

/// App-wide DOKK-local pin history.
///
/// Records only actions the user already took inside DOKK. Nothing is imported from
/// macOS Screen Time, workspace telemetry, or other applications. Pin writes that only
/// change folder presentation or bookmarks are ignored. Mode activation does not pass
/// through this store.
@MainActor @Observable
final class DockLocalHistoryStore {
    private(set) var document = DockLocalHistoryDocument()
    private(set) var requiresReset = false
    private(set) var storageFailed = false
    @ObservationIgnored private let repository: DockLocalHistoryRepository

    var events: [DockLocalHistoryEvent] { document.events }
    var recordingEnabled: Bool { document.recordingEnabled }
    /// When true, Browse Local History may preview historical pin order after a short dwell.
    var replayEnabled: Bool { document.replayEnabled }
    var pinArchive: [String: DockPin] { document.pinArchive }
    var isEmpty: Bool { document.events.isEmpty }
    /// Notified after the pin-preview preference is persisted so an open timeline can react.
    @ObservationIgnored var replayEnabledDidChange: (() -> Void)?

    init(repository: DockLocalHistoryRepository = DockLocalHistoryRepository()) {
        self.repository = repository
    }

    /// Loads stored events.
    func start() {
        do {
            if let stored = try repository.load() {
                document = stored
            }
        } catch {
            requiresReset = true
            storageFailed = true
        }
        guard !requiresReset else { return }
        let before = document.events.count
        prune(at: .now)
        if document.events.count != before { persist() }
    }

    func setRecordingEnabled(_ enabled: Bool) {
        guard !requiresReset, document.recordingEnabled != enabled else { return }
        Analytics.shared.featureSettingChanged(.localHistoryRecording, from: AnalyticsValue(!enabled), to: AnalyticsValue(enabled))
        document.recordingEnabled = enabled
        persist()
    }

    /// Turns historical pin preview on or off. Off is the default, including for older documents.
    func setReplayEnabled(_ enabled: Bool) {
        guard !requiresReset, document.replayEnabled != enabled else { return }
        Analytics.shared.featureSettingChanged(.localHistoryReplay, from: AnalyticsValue(!enabled), to: AnalyticsValue(enabled))
        document.replayEnabled = enabled
        persist()
        replayEnabledDidChange?()
    }

    /// Compares two persisted pin lists and records user-visible add, remove, and reorder events.
    func recordPinChange(previous: [DockPin], next: [DockPin], displayID: String, at date: Date = .now) {
        guard !requiresReset, document.recordingEnabled else { return }
        let mutations = DockLocalHistoryPinDiff.mutations(previous: previous, next: next)
        guard !mutations.isEmpty else { return }
        archive(previous + next)
        let pinIDs = snapshotIDs(next)
        for mutation in mutations {
            let event: DockLocalHistoryEvent
            switch mutation {
            case .added(let id, let name):
                event = makeEvent(kind: .pinAdded, at: date, displayID: displayID,
                                  subjectID: id, subjectName: name, pinIDs: pinIDs)
            case .removed(let id, let name):
                event = makeEvent(kind: .pinRemoved, at: date, displayID: displayID,
                                  subjectID: id, subjectName: name, pinIDs: pinIDs)
            case .moved(let id, let name):
                event = makeEvent(kind: .pinMoved, at: date, displayID: displayID,
                                  subjectID: id, subjectName: name, pinIDs: pinIDs)
            case .reordered:
                event = makeEvent(kind: .pinsReordered, at: date, displayID: displayID,
                                  pinIDs: pinIDs)
            }
            append(event)
        }
        prune(at: date)
        persist()
    }

    func clear() {
        guard !requiresReset else { return }
        document.events = []
        document.pinArchive = [:]
        storageFailed = false
        persistRemovingIfEmpty()
    }

    /// Replaces a corrupt document after an explicit reset. Recording starts enabled.
    func reset() {
        document = DockLocalHistoryDocument()
        requiresReset = false
        storageFailed = false
        repository.remove()
    }

    private func makeEvent(kind: DockLocalHistoryEvent.Kind, at date: Date, displayID: String? = nil,
                           subjectID: String? = nil, subjectName: String? = nil,
                           pinIDs: [String]? = nil) -> DockLocalHistoryEvent {
        DockLocalHistoryEvent(
            id: UUID(),
            occurredAt: date,
            kind: kind,
            displayID: displayID.map { String($0.prefix(256)) },
            subjectID: subjectID.map { String($0.prefix(4096)) },
            subjectName: subjectName.map { String($0.prefix(512)) },
            pinIDs: pinIDs
        )
    }

    private func snapshotIDs(_ pins: [DockPin]) -> [String] {
        Array(pins.prefix(DockLocalHistoryLimits.maximumPinsPerSnapshot).map { String($0.id.prefix(4096)) })
    }

    /// Keeps enough ``DockPin`` records to resolve later preview. Removed pins stay until prune.
    private func archive(_ pins: [DockPin]) {
        for pin in pins.prefix(DockLocalHistoryLimits.maximumArchivedPins) {
            document.pinArchive[pin.id] = pin
        }
    }

    private func append(_ event: DockLocalHistoryEvent) {
        document.events.append(event)
        document.events.sort {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func prune(at date: Date) {
        let cutoff = date.addingTimeInterval(-DockLocalHistoryLimits.retention)
        document.events.removeAll { $0.occurredAt < cutoff }
        if document.events.count > DockLocalHistoryLimits.maximumEvents {
            document.events = Array(document.events.suffix(DockLocalHistoryLimits.maximumEvents))
        }
        pruneArchive()
    }

    private func pruneArchive() {
        var referenced: Set<String> = []
        for event in document.events {
            if let ids = event.pinIDs { referenced.formUnion(ids) }
            if let subjectID = event.subjectID { referenced.insert(subjectID) }
        }
        if referenced.count < document.pinArchive.count {
            document.pinArchive = document.pinArchive.filter { referenced.contains($0.key) }
        }
        let limit = DockLocalHistoryLimits.maximumArchivedPins
        guard document.pinArchive.count > limit else { return }
        var kept: [String: DockPin] = [:]
        let newestIDs = document.events.reversed().lazy.flatMap { event -> [String] in
            (event.pinIDs ?? []) + [event.subjectID].compactMap { $0 }
        }
        for id in newestIDs {
            guard let pin = document.pinArchive[id], kept[id] == nil else { continue }
            kept[id] = pin
            if kept.count == limit { break }
        }
        document.pinArchive = kept
    }

    private func persist() {
        do {
            try repository.save(document)
            storageFailed = false
        } catch {
            storageFailed = true
        }
    }

    private func persistRemovingIfEmpty() {
        if document.events.isEmpty, document.recordingEnabled, !document.replayEnabled,
           document.pinArchive.isEmpty {
            repository.remove()
            storageFailed = false
            return
        }
        persist()
    }
}
