import ClaudeForFoundationModels
import Foundation
import FoundationModels

extension AIObservability.ErrorCode {
    /// The closed code for a failed generation, from Foundation Models, the Claude provider, or the
    /// network. Never reads the error's message, so nothing the server or the prompt said can reach
    /// observability through it.
    nonisolated init(_ error: Error) {
        if let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: self = .contextExceeded
            case .rateLimited: self = .rateLimited
            case .guardrailViolation: self = .guardrail
            case .refusal: self = .refusal
            case .unsupportedLanguageOrLocale: self = .unsupportedLanguage
            case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide: self = .unsupported
            case .timeout: self = .timeout
            default: self = .other
            }
            return
        }
        if let error = error as? ClaudeError {
            switch error {
            case .missingCredential, .attestationUnsupported, .attestationFailed: self = .credential
            }
            return
        }
        if error is SystemLanguageModel.Error {
            self = .unavailable
            return
        }
        if error is PrivateCloudComputeLanguageModel.Error {
            self = .network
            return
        }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff: self = .offline
            case .timedOut: self = .timeout
            default: self = .network
            }
            return
        }
        self = .other
    }
}
