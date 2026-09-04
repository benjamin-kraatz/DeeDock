import Foundation

/// Stable, privacy-bounded identity for a window the user included in a capsule.
///
/// Window numbers and captured pixels are intentionally absent because neither is durable across
/// app launches. The bundle identifier and title are enough to make a best-effort return later.
nonisolated struct SessionCapsuleWindowReference: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let applicationName: String
    let bundleIdentifier: String?
    let windowTitle: String?

    init(id: UUID = UUID(), applicationName: String, bundleIdentifier: String?, windowTitle: String?) {
        self.id = id
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
    }
}

/// A user-approved checkpoint. Raw screenshots and OCR never enter this persisted value.
nonisolated struct SessionCapsule: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var summary: String
    var unfinishedTasks: [String]
    var windows: [SessionCapsuleWindowReference]
    var note: String
    let createdAt: Date

    init(id: UUID = UUID(), title: String, summary: String, unfinishedTasks: [String],
         windows: [SessionCapsuleWindowReference], note: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.summary = summary
        self.unfinishedTasks = unfinishedTasks
        self.windows = windows
        self.note = note
        self.createdAt = createdAt
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && windows.count <= SessionCapsuleDocument.maximumWindowsPerCapsule
    }
}

/// Versioned, app-wide storage for the small set of saved checkpoints.
nonisolated struct SessionCapsuleDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let capacity = 30
    static let maximumWindowsPerCapsule = 12

    var version: Int = Self.currentVersion
    var capsules: [SessionCapsule] = []

    var isValid: Bool {
        version == Self.currentVersion && capsules.count <= Self.capacity
            && Set(capsules.map(\.id)).count == capsules.count
            && capsules.allSatisfy(\.isValid)
    }
}

/// Editable result shown before a capsule can be persisted.
nonisolated struct SessionCapsuleDraft: Equatable, Sendable {
    var title: String
    var summary: String
    var unfinishedTasks: [String]
    let windows: [SessionCapsuleWindowReference]
    var note: String

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func capsule() -> SessionCapsule {
        SessionCapsule(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            unfinishedTasks: unfinishedTasks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            windows: windows,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
