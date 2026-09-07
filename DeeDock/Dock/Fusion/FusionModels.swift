import Foundation

nonisolated enum FusionOperation: String, CaseIterable, Identifiable, Sendable {
    case compare, differences, checklist
    var id: Self { self }
    var label: LocalizedStringResource {
        switch self {
        case .compare: .fusionCompare
        case .differences: .fusionDifferences
        case .checklist: .fusionChecklist
        }
    }
}

/// Reviewed text lives only in memory, for at most fifteen minutes after capture.
/// Images are released immediately after OCR; neither images nor raw OCR are saved to Shelf.
nonisolated struct FusionSource: Identifiable, Sendable {
    let candidate: WindowContextCandidate
    var capturedAt: Date?
    var captureState: FusionCaptureState = .notCaptured
    var text = ""
    var edited = false
    var id: UInt32 { candidate.id }
    var title: String { candidate.title ?? String(localized: .applicationMenuUntitledWindow) }
}

nonisolated enum FusionCaptureState: Sendable {
    case notCaptured, visibleText, truncated, unreadable, unavailable
    var label: LocalizedStringResource {
        switch self {
        case .notCaptured: .fusionNotCaptured
        case .visibleText: .fusionVisibleText
        case .truncated: .fusionTruncated
        case .unreadable: .fusionUnreadable
        case .unavailable: .fusionSourceUnavailable
        }
    }
}

/// Attribution is frozen at generation time and never comes from model output.
nonisolated struct FusionProvenance: Identifiable, Sendable {
    let id: UInt32
    let application: String
    let title: String
    let bundleIdentifier: String?
    let capturedAt: Date?
    let state: FusionCaptureState
    let edited: Bool

    init(_ source: FusionSource) {
        id = source.id
        application = source.candidate.applicationName
        title = source.title
        bundleIdentifier = source.candidate.bundleIdentifier
        capturedAt = source.capturedAt
        state = source.captureState
        edited = source.edited
    }
}

nonisolated struct FusionDraft: Sendable {
    var title: String
    var body: String
    let operation: FusionOperation
    let sources: [FusionProvenance]
    let generatedAt: Date

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 160
            && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && body.count <= 20_000
            && sources.count == 2
    }
}

nonisolated enum FusionFailure: Error, LocalizedError, Sendable {
    case modelUnavailable, contextLimit, refused, invalidOutput, timeout, captureDenied, captureFailed, saveFailed
    var errorDescription: String? {
        switch self {
        case .modelUnavailable: String(localized: .fusionModelUnavailable)
        case .contextLimit: String(localized: .fusionContextLimit)
        case .refused: String(localized: .fusionRefused)
        case .invalidOutput: String(localized: .fusionGenerationFailed)
        case .timeout: String(localized: .fusionTimeout)
        case .captureDenied: String(localized: .fusionCaptureDenied)
        case .captureFailed: String(localized: .fusionCaptureFailed)
        case .saveFailed: String(localized: .fusionSaveFailed)
        }
    }
}
