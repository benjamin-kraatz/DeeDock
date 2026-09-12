import Foundation

/// Text-only evidence from a displayed Peek. No image or live window handle is persisted.
nonisolated struct PeekHistoryEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let capturedAt: Date
    let appName: String
    let windowTitle: String
    let text: String
}

/// Serializes local disk access outside the main actor. The bounded document is the v0 search index.
actor PeekHistoryRepository {
    private let file: URL

    init(file: URL) { self.file = file }

    func load() throws -> [PeekHistoryEntry] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 40_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        let entries = try JSONDecoder().decode([PeekHistoryEntry].self, from: Data(contentsOf: file))
        let retained = Self.retained(entries)
        if retained.count != entries.count { try save(retained) }
        return retained
    }

    func save(_ entries: [PeekHistoryEntry]) throws {
        let manager = FileManager.default
        if entries.isEmpty {
            if manager.fileExists(atPath: file.path) { try manager.removeItem(at: file) }
            return
        }
        var directory = file.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(entries).write(to: file, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    nonisolated static func retained(_ entries: [PeekHistoryEntry], now: Date = .now) -> [PeekHistoryEntry] {
        Array(entries.filter { $0.capturedAt > now.addingTimeInterval(-7 * 24 * 60 * 60) }
            .sorted { $0.capturedAt > $1.capturedAt }.prefix(500))
    }
}
