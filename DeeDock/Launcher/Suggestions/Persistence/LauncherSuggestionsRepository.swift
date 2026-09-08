import Foundation

/// Serial disk owner. Sequence checks reject delayed writes submitted before a newer reset.
/// The actor never suspends between checking a sequence and atomically replacing the file.
actor LauncherSuggestionsRepository {
    private let directory: URL?
    private var latestSequence: UInt64 = 0
    init(directory: URL?) { self.directory = directory }

    func load() throws -> LauncherSuggestionDocument {
        guard let directory else { return LauncherSuggestionDocument() }
        let url = directory.appendingPathComponent("history-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return LauncherSuggestionDocument() }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 64 * 1024 * 1024 else { throw Failure.unreadable }
        let result = try JSONDecoder().decode(LauncherSuggestionDocument.self, from: Data(contentsOf: url))
        guard result.version == 1 else { throw Failure.unreadable }
        return result
    }

    @discardableResult func save(_ document: LauncherSuggestionDocument, sequence: UInt64) throws -> LauncherSuggestionDocument {
        guard sequence >= latestSequence else { return document }
        latestSequence = sequence
        guard let directory else { return document }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        var privateDirectory = directory
        var resources = URLResourceValues(); resources.isExcludedFromBackup = true
        try privateDirectory.setResourceValues(resources)
        var retained = document
        var data = try JSONEncoder().encode(retained)
        // Count limits alone cannot bound variable-length context. Leave room below the load
        // guard, retaining the newest half of each collection until the serialized file fits.
        // Returning the retained document also retires its effective in-memory learning.
        while data.count > 16 * 1024 * 1024 {
            retained.events = Array(retained.events.suffix(retained.events.count / 2))
            retained.examples = Array(retained.examples.suffix(retained.examples.count / 2))
            retained.feedback = Array(retained.feedback.suffix(retained.feedback.count / 2))
            retained.impressions = Array(retained.impressions.suffix(retained.impressions.count / 2))
            retained.promptAnswers = Array(retained.promptAnswers.suffix(retained.promptAnswers.count / 2))
            data = try JSONEncoder().encode(retained)
        }
        let url = directory.appendingPathComponent("history-v1.json")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return retained
    }

    enum Failure: Error { case unreadable }
}
