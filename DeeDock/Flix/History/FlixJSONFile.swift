import Foundation
import os

/// One JSON document on disk, read once and written behind a short debounce off the main actor.
///
/// Writes are atomic (`Data.write(options: .atomic)`), so a crash mid-write leaves the previous
/// version. Each ``schedule(_:)`` replaces the pending value; only the newest one is written. A
/// write already running finishes before the next one starts, because both go through one serial
/// queue. ``flush()`` writes synchronously, for quit.
nonisolated final class FlixJSONFile<Value: Codable & Sendable>: @unchecked Sendable {
    let url: URL
    private let queue: DispatchQueue
    private let delay: DispatchTimeInterval
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var pending: Value?
    private var scheduled = false
    private static var logger: Logger { Logger(subsystem: Bundle.main.bundleIdentifier ?? "DeeDock", category: "Flix") }

    /// - Parameter delay: How long writes coalesce. Every change within it costs one write.
    init(url: URL, delay: DispatchTimeInterval = .milliseconds(800)) {
        self.url = url
        self.delay = delay
        queue = DispatchQueue(label: "dokk.flix.file.\(url.lastPathComponent)", qos: .utility)
    }

    /// The saved value, nil when there is no file yet.
    ///
    /// - Throws: The file exists but cannot be read or decoded. Callers move it aside with
    ///   ``quarantine()`` before writing a new one.
    func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(Value.self, from: data)
    }

    /// Moves an unreadable file aside as `<name>.unreadable-<timestamp>.json`, so the next write
    /// starts a fresh one without destroying data a newer DOKK might still read.
    func quarantine() {
        let stamp = Int(Date.now.timeIntervalSince1970)
        let name = url.deletingPathExtension().lastPathComponent + ".unreadable-\(stamp).json"
        try? FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appending(path: name))
    }

    /// Writes `value` after the debounce, replacing any write still waiting.
    func schedule(_ value: Value) {
        lock.lock()
        pending = value
        let start = !scheduled
        scheduled = true
        lock.unlock()
        guard start else { return }
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.writePending() }
    }

    /// Writes any waiting value now and returns when it is on disk.
    func flush() {
        queue.sync { writePending() }
    }

    private func writePending() {
        lock.lock()
        let value = pending
        pending = nil
        scheduled = false
        lock.unlock()
        guard let value else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            Self.logger.error("Could not save \(self.url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Where Flix Files keeps its files: `~/Library/Application Support/DDock/Flix/` for the release
/// app and `DDock/Flix-dev/` for a development build, the same split Lookout makes, so a debug
/// build never rewrites the release app's history.
nonisolated enum FlixStorageLocation {
    static let releaseIdentifier = "de.benjaminkraatz.DeeDock"

    static func folder(bundleIdentifier: String? = Bundle.main.bundleIdentifier,
                       applicationSupport: URL = .applicationSupportDirectory) -> URL {
        applicationSupport.appending(path: "DDock/" + folderName(bundleIdentifier: bundleIdentifier),
                                     directoryHint: .isDirectory)
    }

    /// `Flix` for the release identity, `Flix-dev` for `….DeeDock.dev`, `Flix-<identifier>` otherwise.
    static func folderName(bundleIdentifier: String?) -> String {
        let identifier = bundleIdentifier ?? releaseIdentifier
        guard identifier != releaseIdentifier else { return "Flix" }
        let suffix = identifier.hasPrefix(releaseIdentifier + ".")
            ? String(identifier.dropFirst(releaseIdentifier.count + 1)) : identifier
        let safe = String(suffix.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" ? Character(scalar) : "-"
        })
        return "Flix-" + (safe.isEmpty ? "unknown" : safe)
    }
}
