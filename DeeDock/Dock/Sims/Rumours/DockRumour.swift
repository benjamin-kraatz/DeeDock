import Foundation

/// Only visible app names and fictional pet moods are supplied to the model.
nonisolated struct DockRumourParticipant: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let mood: String
}

/// A complete, validated exchange. Generated text is displayed verbatim, never localized as a key.
nonisolated struct DockRumour: Sendable {
    let turns: [Turn]

    struct Turn: Sendable {
        let speakerID: String
        let message: String
    }
}

/// Availability and failures are explained in Settings without interrupting dock interaction.
nonisolated enum DockRumourStatus: Equatable, Sendable {
    case ready, deviceNotEligible, intelligenceDisabled, modelNotReady, unsupportedLanguage, generationFailed, invalidOutput

    var message: LocalizedStringResource? {
        switch self {
        case .ready: nil
        case .deviceNotEligible: .simsRumourDeviceUnavailable
        case .intelligenceDisabled: .simsRumourIntelligenceDisabled
        case .modelNotReady: .simsRumourModelNotReady
        case .unsupportedLanguage: .simsRumourUnsupportedLanguage
        case .generationFailed: .simsRumourGenerationFailed
        case .invalidOutput: .simsRumourInvalidOutput
        }
    }
}
