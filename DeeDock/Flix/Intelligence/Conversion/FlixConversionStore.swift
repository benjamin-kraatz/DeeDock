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
@MainActor @Observable
final class FlixConversionStore {
    static let concurrentLimit = 2
    static let lifetime: TimeInterval = 2 * 3_600

    /// Bumped whenever a conversion finishes, so views that show a conversion label redraw.
    private(set) var version = 0

    @ObservationIgnored private var ready: [Key: FlixPreparedConversion] = [:]
    @ObservationIgnored private var running: [Key: Task<Void, Never>] = [:]
    @ObservationIgnored private var waiting: [(Key, UTType, String)] = []
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
    func prepare(_ items: [FlixItem], for demand: FlixWindowDemand, policy: FlixReadPolicy) {
        guard demand.hasLimits else { return }
        self.policy = policy
        pruneOld()
        for item in items {
            guard case .convert(let recipe) = FlixConversionPlanner.decision(for: item, demand: demand),
                  let path = item.path, policy.canRead(path),
                  let type = item.contentType ?? UTType(filenameExtension: (path as NSString).pathExtension) else { continue }
            let key = Key(path: path, recipe: recipe)
            if let existing = ready[key], existing.sourceModified == Self.modified(path) { continue }
            if let refused = declined[key], refused == Self.modified(path) { continue }
            guard running[key] == nil, !waiting.contains(where: { $0.0 == key }) else { continue }
            waiting.append((key, type, item.name))
        }
        startWaiting()
    }

    /// The copy for `item` under `recipe`, if one is ready and still matches the original.
    func prepared(for item: FlixItem, recipe: FlixConversionRecipe) -> FlixPreparedConversion? {
        _ = version
        guard let path = item.path, let conversion = ready[Key(path: path, recipe: recipe)],
              FileManager.default.fileExists(atPath: conversion.url.path),
              conversion.sourceModified == Self.modified(path) else { return nil }
        return conversion
    }

    /// Whether the converter declined `item` under `recipe` because a copy would leave part of it
    /// out; such an item goes out unchanged, without a conversion label.
    func isDeclined(_ item: FlixItem, recipe: FlixConversionRecipe) -> Bool {
        guard let path = item.path, let refused = declined[Key(path: path, recipe: recipe)] else { return false }
        return refused == Self.modified(path)
    }

    /// Cancels running conversions and removes every copy.
    func stop() {
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
            let modified = Self.modified(key.path)
            let policy = policy
            running[key] = Task(priority: .utility) { [weak self] in
                let started = ContinuousClock.now
                // `convert` is `@concurrent`, so the work leaves the main actor; cancelling this task
                // cancels it too. It opens the file through `FlixSafeFile`, re-checking the policy.
                let result: (url: URL, bytes: Int64)?
                var omits = false
                do {
                    result = try await FlixFileConverter.convert(key.path, policy: policy, type: type, recipe: key.recipe,
                                                                 name: name, into: destination)
                } catch FlixFileConverter.ConversionError.wouldOmitContent {
                    result = nil
                    omits = true
                } catch {
                    result = nil
                }
                guard let self else { return }
                running[key] = nil
                if omits, !Task.isCancelled { declined[key] = .some(modified) }
                if let result, !Task.isCancelled {
                    let elapsed = ContinuousClock.now - started
                    ready[key] = FlixPreparedConversion(url: result.url, bytes: result.bytes, recipe: key.recipe,
                                                        sourceModified: modified, createdAt: .now,
                                                        durationMs: Int(elapsed / .milliseconds(1)))
                    version += 1
                }
                startWaiting()
            }
        }
    }

    private func pruneOld() {
        let cutoff = Date.now.addingTimeInterval(-Self.lifetime)
        for (key, conversion) in ready where conversion.createdAt < cutoff {
            try? FileManager.default.removeItem(at: conversion.url.deletingLastPathComponent())
            ready[key] = nil
        }
    }

    private static func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
