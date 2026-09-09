import Foundation

/// Optional app and title hints used only to suggest presets. They never identify a window.
nonisolated struct WindowWatchAppHint: Codable, Equatable, Sendable {
    var bundleIdentifier: String?
    var appName: String
    var title: String

    var isValid: Bool {
        (bundleIdentifier?.count ?? 0) <= 256
            && appName.count <= 256
            && title.count <= 512
            && !(appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 && (bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
    }
}

/// Configuration copied onto a run. Folder bookmarks and Shortcut IDs are user-chosen, not inferred.
nonisolated enum WindowWatchCompletionAction: Codable, Equatable, Sendable {
    case none
    case openFolder(bookmark: Data, name: String)
    case runShortcut(id: UUID, name: String)

    var isConfigured: Bool {
        switch self {
        case .none: false
        case .openFolder, .runShortcut: true
        }
    }

    var isValid: Bool {
        switch self {
        case .none:
            true
        case .openFolder(let bookmark, let name):
            !bookmark.isEmpty && bookmark.count <= 65_536
                && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && name.count <= 256
        case .runShortcut(_, let name):
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 256
        }
    }
}

/// The durable fields of a saved watch, excluding its name and timestamps.
nonisolated struct WindowWatchPresetConfiguration: Codable, Equatable, Sendable {
    var region: NormalizedWindowRegion
    var usesPhrase: Bool
    var phrase: String
    var playSound: Bool
    var completion: WindowWatchCompletionAction
    var appHint: WindowWatchAppHint?

    var isValid: Bool {
        let clamped = region.clamped
        return clamped.width >= 0.05 && clamped.height >= 0.05
            && phrase.count <= 512
            && (!usesPhrase || !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && completion.isValid
            && (appHint?.isValid ?? true)
    }

    func normalized() -> Self {
        var next = self
        next.region = region.clamped
        next.phrase = String(phrase.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
        return next
    }
}

/// A named, persisted watch configuration. No screenshot, OCR, capture buffer, or window ID is stored.
nonisolated struct WindowWatchPreset: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var configuration: WindowWatchPresetConfiguration
    var createdAt: Date
    var updatedAt: Date

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.count <= 80
            && configuration.isValid
    }

    func matching(bundleIdentifier: String?, appName: String) -> Bool {
        guard let hint = configuration.appHint else { return false }
        if let stored = hint.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty,
           let current = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !current.isEmpty {
            return stored == current
        }
        let storedName = hint.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !storedName.isEmpty && storedName.caseInsensitiveCompare(currentName) == .orderedSame
    }
}

/// Versioned preset list. Unreadable bytes stay in storage until an explicit reset.
nonisolated struct WindowWatchPresetDocument: Codable, Equatable, Sendable {
    static let capacity = 30
    var version = 1
    var presets: [WindowWatchPreset] = []

    var isValid: Bool {
        version == 1
            && presets.count <= Self.capacity
            && Set(presets.map(\.id)).count == presets.count
            && presets.allSatisfy(\.isValid)
    }
}

/// How a watch ended. Only a detector completion can expose a success-triggered action.
nonisolated enum WindowWatchRunOutcome: Equatable, Sendable {
    case watching, detected, cancelled, failed
}

/// Execution of one configured completion action for one run.
nonisolated enum WindowWatchActionPhase: Equatable, Sendable {
    case idle, running, succeeded, failed
}

/// Snapshot bound to an explicitly started watch. Later preset edits do not rewrite it.
nonisolated struct WindowWatchRunSnapshot: Equatable, Sendable {
    let runID: UUID
    let presetID: UUID?
    let presetName: String?
    let configuration: WindowWatchPresetConfiguration
}

/// Prevents late frames, repeated detector results, and rapid clicks from running an action twice.
nonisolated struct WindowWatchActionGate: Equatable, Sendable {
    var runID: UUID
    var outcome: WindowWatchRunOutcome
    var action: WindowWatchCompletionAction
    var phase: WindowWatchActionPhase = .idle

    /// Shown only after the detector finished. Cancelled and failed watches stay silent.
    var canOffer: Bool {
        outcome == .detected && action.isConfigured && phase != .running && phase != .succeeded
    }

    /// Failure can be retried after a repair. Success and in-flight work cannot.
    var canBegin: Bool {
        outcome == .detected && action.isConfigured && (phase == .idle || phase == .failed)
    }

    mutating func begin(_ requested: UUID) -> Bool {
        guard requested == runID, canBegin else { return false }
        phase = .running
        return true
    }

    mutating func finish(success: Bool) {
        guard phase == .running else { return }
        phase = success ? .succeeded : .failed
    }
}

/// Whether a saved preset still matches the snapshot a run started with.
nonisolated enum WindowWatchPresetDrift: Equatable, Sendable {
    case deleted, edited
}
