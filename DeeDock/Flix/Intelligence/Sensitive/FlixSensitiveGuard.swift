import Foundation
import UniformTypeIdentifiers

/// The saved verdicts of the sensitive file guard, and the files the person marked as not
/// sensitive. `sensitive.json` next to the history.
nonisolated struct FlixSensitiveDocument: Codable, Sendable {
    struct Entry: Codable, Sendable {
        /// The file's modification date when it was checked; a newer file is checked again.
        var modified: Date?
        var kind: FlixSensitiveKind?
    }

    var entries: [String: Entry] = [:]
    /// Paths marked **Not Sensitive**. They stay unmarked even when the file changes.
    var cleared: Set<String> = []

    /// Keeps the file bounded. Past this many entries, clean verdicts are dropped (in no particular
    /// order) and sensitive ones kept; a dropped file is simply checked again when it shows up.
    static let entryLimit = 6_000

    mutating func trim() {
        guard entries.count > Self.entryLimit else { return }
        let clean = entries.filter { $0.value.kind == nil }.map(\.key)
        for path in clean.prefix(entries.count - Self.entryLimit) { entries[path] = nil }
    }
}

/// The sensitive file guard: checks files once in the background, blurs what looks like an ID,
/// bank details, or a key, and asks before such a file leaves for a browser, mail, or chat.
///
/// - **When**: every history change hands over the items (``update(items:policy:)``); new and
///   changed files join a queue, newest first, at most ``passLimit`` per pass. Verdicts are cached by
///   path and modification date in `sensitive.json`, so a file is read once, not once per launch.
/// - **What it reads**: only files ``FlixReadPolicy`` allows, so the guard can never make macOS ask
///   for folder access; at most one file at a time, at utility priority, through
///   ``FlixSensitiveScanner``.
/// - **Results**: pushed through ``verdictChanged`` as they arrive; the coordinator writes them into
///   the item's annotation (`isSensitive`, `sensitiveReason`), which blurs the row, the tile, and the
///   drag picture.
/// - **Not Sensitive**: ``markNotSensitive(_:)`` stores the path; it is never flagged again.
///
/// The worker task belongs to the guard and is cancelled by ``stop()`` or by switching the guard
/// off. Main actor.
@MainActor
final class FlixSensitiveGuard {
    static let passLimit = 300

    /// An item's verdict changed: nil means not sensitive.
    var verdictChanged: ((FlixItem.ID, FlixSensitiveKind?) -> Void)?

    private var document = FlixSensitiveDocument()
    private let file: FlixJSONFile<FlixSensitiveDocument>?
    private var queue: [FlixItem] = []
    private var queued = Set<String>()
    private var worker: Task<Void, Never>?
    /// Identifies the current worker, so a cancelled one finishing late does not clear its successor.
    private var workerGeneration = 0
    /// The verdict most recently reported per item, so unchanged verdicts are not pushed again.
    private var reported: [FlixItem.ID: FlixSensitiveKind?] = [:]
    private var loaded = false
    private(set) var isEnabled = false

    /// - Parameter folder: Where `sensitive.json` lives; nil keeps verdicts in memory.
    init(folder: URL?) {
        file = folder.map { FlixJSONFile(url: $0.appending(path: "sensitive.json")) }
    }

    /// Turns the guard on or off. Off cancels the worker and clears every blur it set.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled {
            worker?.cancel()
            worker = nil
            queue = []
            queued = []
            for (id, kind) in reported where kind != nil { verdictChanged?(id, nil) }
            reported = [:]
        }
    }

    /// The history changed. Reports cached verdicts at once and queues files not checked yet.
    func update(items: [FlixItem], policy: FlixReadPolicy) {
        guard isEnabled else { return }
        loadIfNeeded()
        var added = 0
        for item in items {
            guard added < Self.passLimit, let path = item.path, Self.isCandidate(item), policy.canRead(path) else { continue }
            if let entry = document.entries[path] {
                report(item, kind: document.cleared.contains(path) ? nil : entry.kind)
                // A file written after its check is checked again; the worker compares the real
                // modification date off the main actor. Opening a file does not change it.
                let written = item.activity == .saved || item.activity == .created || item.activity == .downloaded
                guard written, let checked = entry.modified, item.date.timeIntervalSince(checked) > 1 else { continue }
            }
            if queued.insert(path).inserted {
                queue.append(item)
                added += 1
            }
        }
        startWorker()
    }

    /// The current verdict for an item, from memory. Synchronous, for the drag hooks.
    func verdict(for item: FlixItem) -> FlixSensitiveKind? {
        guard isEnabled, let path = item.path, !document.cleared.contains(path) else { return nil }
        return document.entries[path]?.kind
    }

    /// **Not Sensitive**: the file is never flagged again.
    func markNotSensitive(_ item: FlixItem) {
        guard let path = item.path else { return }
        loadIfNeeded()
        document.cleared.insert(path)
        save()
        report(item, kind: nil)
    }

    func stop() {
        worker?.cancel()
        worker = nil
        queue = []
        queued = []
        file?.flush()
    }

    // MARK: Pieces

    static func isCandidate(_ item: FlixItem) -> Bool {
        switch item.kind {
        case .image, .screenshot, .document, .other: true
        case .folder, .app, .link: false
        }
    }

    /// Pushes a verdict when it differs from the last one pushed for the item (a first "not
    /// sensitive" needs no push: unflagged is the default).
    private func report(_ item: FlixItem, kind: FlixSensitiveKind?) {
        let changed = reported[item.id].map { $0 != kind } ?? (kind != nil)
        reported[item.id] = .some(kind)
        if changed { verdictChanged?(item.id, kind) }
    }

    private func startWorker() {
        guard worker == nil, !queue.isEmpty else { return }
        workerGeneration += 1
        let generation = workerGeneration
        worker = Task(priority: .utility) { [weak self] in
            while let self, !Task.isCancelled, !queue.isEmpty {
                let item = queue.removeFirst()
                guard let path = item.path else { continue }
                queued.remove(path)
                let previous = document.entries[path]
                let type = item.contentType ?? UTType(filenameExtension: (path as NSString).pathExtension)
                let outcome = await Self.check(path: path, type: type, kind: item.kind, byteSize: item.byteSize,
                                               previous: previous)
                guard !Task.isCancelled else { break }
                guard let outcome else { continue }
                document.entries[path] = outcome
                document.trim()
                save()
                report(item, kind: document.cleared.contains(path) ? nil : outcome.kind)
            }
            guard let self, workerGeneration == generation else { return }
            worker = nil
        }
    }

    /// Reads the file's date and, when it is new or changed, scans it. Nil when the file is gone.
    @concurrent
    private static func check(path: String, type: UTType?, kind: FlixItemKind, byteSize: Int64?,
                              previous: FlixSensitiveDocument.Entry?) async -> FlixSensitiveDocument.Entry? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let modified = attributes[.modificationDate] as? Date
        if let previous, previous.modified == modified { return previous }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? byteSize
        let verdict = await FlixSensitiveScanner.scan(URL(fileURLWithPath: path), type: type, kind: kind, byteSize: size)
        return FlixSensitiveDocument.Entry(modified: modified, kind: verdict)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        do {
            if let saved = try file?.load() { document = saved }
        } catch {
            file?.quarantine()
        }
    }

    private func save() {
        file?.schedule(document)
    }
}
