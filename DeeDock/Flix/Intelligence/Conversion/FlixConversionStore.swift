import Foundation
import Observation
import UniformTypeIdentifiers

/// A converted copy ready to stand in for a file in a drag.
nonisolated struct FlixPreparedConversion: Equatable, Sendable {
    var url: URL
    var bytes: Int64
    var recipe: FlixConversionRecipe
    /// The original's modification date when it was converted; a newer original makes the copy stale.
    var sourceModified: Date?
    var createdAt: Date
    /// How long making the copy took, in milliseconds.
    var durationMs = 0
}

/// Converted copies for uploads, prepared before a drag starts.
///
/// A drag source cannot convert while the drag runs: the destination reads the file URLs on the
/// pasteboard right away (browsers do not take file promises), so ``prepare(_:for:)`` converts ahead
/// of time — for the Fits rows and the selected rows as soon as the window's limits are known — and
/// ``prepared(for:recipe:)`` answers synchronously at drag start.
///
/// Copies live in `…/T/DOKK Flix Conversions/<random>/<original name>.<ext>` so the destination sees
/// a sensible name. The folder is emptied when Flix Files starts and stops, and copies older than
/// two hours are removed whenever more are prepared; an upload already in progress has read its
/// file by then. Only files the read policy allows are converted, so no conversion can make macOS
/// ask for folder access, and the converter re-checks the policy when it opens each file. A file the
/// converter declines because a copy would leave part of it out (`FlixFileConverter`) is remembered
/// and not tried again until it changes; its drag carries the original. At most
/// ``concurrentLimit`` conversions run at once, off the main actor, each in a task this store owns
/// and cancels on ``stop()``.
///
/// Nothing here touches the disk on the main actor, where a file on a share that went away could
/// stall the dock: ``prepare(_:for:policy:)`` filters by type and the path's spelling, then reads
/// the originals' modification dates in the background (``FlixContentReader/stamps(_:policy:)``,
/// which also resolves each path through the policy) before it queues anything; the converter
/// reports the date of the file it actually read. ``prepared(for:recipe:)`` answers from memory at
/// drag start: a copy counts while the date checked at the last prepare still holds, unless the
/// row's identity records a modification newer than the copy's source.
@MainActor @Observable
final class FlixConversionStore {
    static let concurrentLimit = 2
    static let lifetime: TimeInterval = 2 * 3_600

    /// Bumped whenever a conversion finishes, so views that show a conversion label redraw.
    private(set) var version = 0

    @ObservationIgnored private var ready: [Key: FlixPreparedConversion] = [:]
    @ObservationIgnored private var running: [Key: Task<Void, Never>] = [:]
    @ObservationIgnored private var waiting: [(key: Key, type: UTType, name: String)] = []
    /// The background date check of the latest prepare; a newer prepare replaces it.
    @ObservationIgnored private var checking: Task<Void, Never>?
    /// Conversions the converter declined because a copy would leave something out, with the
    /// original's modification date then; not tried again until the original changes.
    @ObservationIgnored private var declined: [Key: Date?] = [:]
    /// The read policy of the latest ``prepare(_:for:policy:)``, which the converter re-checks when it
    /// opens each file.
    @ObservationIgnored private var policy = FlixReadPolicy(allowedRoots: [])
    @ObservationIgnored let folder: URL

    private struct Key: Hashable {
        var path: String
        var recipe: FlixConversionRecipe
    }

    init(folder: URL = FileManager.default.temporaryDirectory.appending(path: "DOKK Flix Conversions", directoryHint: .isDirectory)) {
        self.folder = folder
    }

    /// Converts what `items` need for `demand`, skipping copies already made or running.
    ///
    /// Picks candidates from memory (type, size, the path's spelling), then reads the originals'
    /// modification dates off the main actor: a ready copy whose original changed is dropped, a
    /// declined file that changed is tried again, and a path the policy refuses is skipped.
    func prepare(_ items: [FlixItem], for demand: FlixWindowDemand, policy: FlixReadPolicy) {
        guard demand.hasLimits else { return }
        self.policy = policy
        pruneOld()
        var candidates: [(key: Key, type: UTType, name: String)] = []
        for item in items {
            guard case .convert(let recipe) = FlixConversionPlanner.decision(for: item, demand: demand),
                  let path = item.path, policy.spellingIsReadable(path),
                  let type = item.contentType ?? UTType(filenameExtension: (path as NSString).pathExtension) else { continue }
            candidates.append((Key(path: path, recipe: recipe), type, item.name))
        }
        guard !candidates.isEmpty else { return }
        checking?.cancel()
        checking = Task { [weak self] in
            let stamps = await FlixContentReader.stamps(Array(Set(candidates.map(\.key.path))), policy: policy)
            guard let self, !Task.isCancelled else { return }
            enqueue(candidates, stamps: stamps)
        }
    }

    /// Queues the candidates whose copy is missing or stale, given their originals' dates now.
    private func enqueue(_ candidates: [(key: Key, type: UTType, name: String)], stamps: [String: FlixFileStamp]) {
        for candidate in candidates {
            let key = candidate.key
            // Gone, or the policy refused it once resolved.
            guard let stamp = stamps[key.path] else {
                if ready[key] != nil { ready[key] = nil; version += 1 }
                continue
            }
            if let existing = ready[key] {
                if Self.sameDate(existing.sourceModified, stamp.modified) { continue }
                ready[key] = nil
                version += 1
            }
            if let refused = declined[key] {
                if Self.sameDate(refused, stamp.modified) { continue }
                declined[key] = nil
            }
            guard running[key] == nil, !waiting.contains(where: { $0.key == key }) else { continue }
            waiting.append(candidate)
        }
        startWaiting()
    }

    /// The copy for `item` under `recipe`, if one is ready and still matches the original.
    ///
    /// From memory, for drag start: the original's date was checked off the main actor at the last
    /// prepare, and a row whose identity records a later modification than the copy's source (the
    /// watcher saw the file saved since) does not get the copy.
    func prepared(for item: FlixItem, recipe: FlixConversionRecipe) -> FlixPreparedConversion? {
        _ = version
        guard let path = item.path, let conversion = ready[Key(path: path, recipe: recipe)] else { return nil }
        if let modified = item.fileIdentity?.modified, let source = conversion.sourceModified {
            let listed = Date(timeIntervalSince1970: TimeInterval(modified) / 1_000_000_000)
            guard listed.timeIntervalSince(source) < 0.001 else { return nil }
        }
        return conversion
    }

    /// Whether the converter declined `item` under `recipe` because a copy would leave part of it
    /// out; such an item goes out unchanged, without a conversion label. From memory: a declined
    /// file that changed is tried again at the next prepare, which clears this.
    func isDeclined(_ item: FlixItem, recipe: FlixConversionRecipe) -> Bool {
        guard let path = item.path else { return false }
        return declined[Key(path: path, recipe: recipe)] != nil
    }

    /// Cancels running conversions and removes every copy.
    func stop() {
        checking?.cancel()
        checking = nil
        running.values.forEach { $0.cancel() }
        running = [:]
        waiting = []
        ready = [:]
        declined = [:]
        removeFolder()
    }

    /// Removes copies left from an earlier run.
    func removeFolder() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func startWaiting() {
        while running.count < Self.concurrentLimit, !waiting.isEmpty {
            let (key, type, name) = waiting.removeFirst()
            let destination = folder.appending(path: String(UUID().uuidString.prefix(8)), directoryHint: .isDirectory)
            let policy = policy
            running[key] = Task(priority: .utility) { [weak self] in
                let started = ContinuousClock.now
                // `convert` is `@concurrent`, so the work leaves the main actor; cancelling this task
                // cancels it too. It opens the file through `FlixSafeFile`, re-checking the policy,
                // and reports the modification date of the file it read.
                var result: (url: URL, bytes: Int64, sourceModified: Date)?
                var omitted: Date?? = nil
                do {
                    result = try await FlixFileConverter.convert(key.path, policy: policy, type: type, recipe: key.recipe,
                                                                 name: name, into: destination)
                } catch FlixFileConverter.ConversionError.wouldOmitContent {
                    omitted = .some(await FlixContentReader.stamps([key.path], policy: policy)[key.path]?.modified)
                } catch {
                    result = nil
                }
                guard let self else { return }
                running[key] = nil
                if let omitted, !Task.isCancelled { declined[key] = omitted }
                if let result, !Task.isCancelled {
                    let elapsed = ContinuousClock.now - started
                    ready[key] = FlixPreparedConversion(url: result.url, bytes: result.bytes, recipe: key.recipe,
                                                        sourceModified: result.sourceModified, createdAt: .now,
                                                        durationMs: Int(elapsed / .milliseconds(1)))
                    version += 1
                }
                startWaiting()
            }
        }
    }

    private func pruneOld() {
        let cutoff = Date.now.addingTimeInterval(-Self.lifetime)
        var expired: [URL] = []
        for (key, conversion) in ready where conversion.createdAt < cutoff {
            expired.append(conversion.url.deletingLastPathComponent())
            ready[key] = nil
        }
        guard !expired.isEmpty else { return }
        // DOKK's own temporary folder, removed in the background like every other file operation here.
        Task.detached(priority: .utility) { for folder in expired { try? FileManager.default.removeItem(at: folder) } }
    }

    /// Whether two modification dates are the same instant, allowing for the precision lost between
    /// `stat`'s nanoseconds and `Date`.
    private static func sameDate(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case (let a?, let b?): abs(a.timeIntervalSince(b)) < 0.001
        default: false
        }
    }
}
