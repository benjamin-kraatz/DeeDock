import Foundation
import FoundationModels

/// Session-only support details. Excludes prompts, app names, and generated dialogue.
nonisolated struct DockRumourDiagnostic {
    let requestID: UUID
    let recordedAt: Date
    let reason: String
    let domain: String
    let code: Int

    init(error: Error, requestID: UUID) {
        self.requestID = requestID
        recordedAt = .now
        let underlying = error as NSError
        domain = underlying.domain
        code = underlying.code
        if case FoundationModelsRumourComposer.Failure.invalidOutput(let details) = error {
            reason = details
        } else if let modelError = error as? LanguageModelError {
            switch modelError {
            case .contextSizeExceeded: reason = "context-size-exceeded"
            case .rateLimited: reason = "rate-limited"
            case .guardrailViolation: reason = "guardrail-violation"
            case .refusal: reason = "model-refusal"
            case .unsupportedCapability: reason = "unsupported-capability"
            case .unsupportedTranscriptContent: reason = "unsupported-transcript"
            case .unsupportedGenerationGuide: reason = "unsupported-generation-guide"
            case .unsupportedLanguageOrLocale: reason = "unsupported-locale"
            case .timeout: reason = "model-timeout"
            @unknown default: reason = "model-error"
            }
        } else {
            reason = "generation-error"
        }
    }

    /// Stable, selectable diagnostic data rather than localized product copy.
    var report: String {
        """
        IconRumours
        time: \(recordedAt.ISO8601Format())
        request: \(requestID.uuidString)
        reason: \(reason)
        error: \(domain) (\(code))
        """
    }
}
