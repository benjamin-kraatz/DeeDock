import Foundation

/// Stable, privacy-bounded identity for a window the user included in a capsule.
///
/// Matching uses app identity and a unique title, never a persisted native window handle.
/// Breadcrumbs may retain a bounded, dated text preview after explicit capture and Save.
nonisolated struct SessionCapsuleWindowReference: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let applicationName: String
    let bundleIdentifier: String?
    let windowTitle: String?
    var observedAt: Date?
    var capturedAt: Date?
    var textPreview: String?
    /// Only user-supplied HTTP(S) links are eligible for reopening.
    var link: String?
    var documentBookmark: Data?
    var documentName: String?

    var reopeningURL: URL? {
        guard let link, link.count <= 2_048, let url = URL(string: link),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return url
    }

    var isValid: Bool {
        (textPreview?.count ?? 0) <= 2_000
            && (textPreview == nil || capturedAt != nil)
            && (link?.count ?? 0) <= 2_048
            && (link?.isEmpty != false || reopeningURL != nil)
            && (documentBookmark?.count ?? 0) <= 65_536
    }

    init(id: UUID = UUID(), applicationName: String, bundleIdentifier: String?, windowTitle: String?) {
        self.id = id
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
    }
}

/// Optional breadcrumb fields extend the existing v1 document without invalidating older saves.
nonisolated struct SessionCapsuleBreadcrumb: Codable, Equatable, Sendable {
    var nextStep = ""
    /// Non-nil only after model output is supplied; personal notes are never model output.
    var generatedAt: Date?
}

/// A user-approved checkpoint. Breadcrumb previews contain at most 2,000 OCR characters per source.
/// No screenshot, live handle, or window geometry is persisted.
nonisolated struct SessionCapsule: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var summary: String
    var unfinishedTasks: [String]
    var windows: [SessionCapsuleWindowReference]
    var note: String
    let createdAt: Date
    var breadcrumb: SessionCapsuleBreadcrumb?

    init(id: UUID = UUID(), title: String, summary: String, unfinishedTasks: [String],
         windows: [SessionCapsuleWindowReference], note: String, createdAt: Date = Date(), breadcrumb: SessionCapsuleBreadcrumb? = nil) {
        self.id = id
        self.title = title
        self.summary = summary
        self.unfinishedTasks = unfinishedTasks
        self.windows = windows
        self.note = note
        self.createdAt = createdAt
        self.breadcrumb = breadcrumb
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (breadcrumb == nil ? !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                : !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !(breadcrumb?.nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
            && windows.count <= SessionCapsuleDocument.maximumWindowsPerCapsule
            && windows.allSatisfy(\.isValid)
            && (breadcrumb == nil || (title.count <= 200 && summary.count <= 8_000
                && note.count <= 8_000 && (breadcrumb?.nextStep.count ?? 0) <= 2_000
                && unfinishedTasks.count <= 6 && unfinishedTasks.allSatisfy { $0.count <= 2_000 }))
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
    var windows: [SessionCapsuleWindowReference]
    var note: String
    var breadcrumb: SessionCapsuleBreadcrumb? = nil
    var editingID: UUID? = nil
    var originalCreatedAt: Date? = nil

    var canSave: Bool { capsule().isValid }

    func capsule() -> SessionCapsule {
        SessionCapsule(
            id: editingID ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            unfinishedTasks: unfinishedTasks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            windows: windows,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: originalCreatedAt ?? Date(), breadcrumb: breadcrumb
        )
    }
}
