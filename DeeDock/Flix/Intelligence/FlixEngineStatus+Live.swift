import Foundation
import FoundationModels

extension FlixEngineStatus {
    /// What this Mac offers right now, for Settings' "What powers it" rows: Lookout from its settings,
    /// Apple Intelligence from the system model's availability, Robi from the model Robi's settings
    /// choose (Apple Intelligence on this Mac needs no key; Claude needs a saved key). Reads no files
    /// and starts nothing.
    ///
    /// - Parameters:
    ///   - lookout: Lookout's current settings; nil reads the saved ones.
    ///   - robi: Robi's settings and key; nil marks Robi unavailable.
    @MainActor
    static func current(lookout: LookoutSettings? = nil, robi: RobiStore?) -> FlixEngineStatus {
        let lookout = lookout ?? LookoutSettingsRepository(defaults: .standard).loadOrDefault()
        let lookoutState: State = lookout.isActive ? .ready(detail: lookout.selection.folders.count)
            : lookout.setupCompleted ? .off : .needsSetup
        let appleState = state(of: SystemLanguageModel.default.availability)
        var status = FlixEngineStatus(lookout: lookoutState, appleIntelligence: appleState)
        if let robi {
            switch robi.settings.answerModel {
            case .onDevice:
                status.robi = appleState
                status.robiOnDevice = true
            case .claude:
                status.robi = robi.hasClaudeKey ? .ready(detail: nil) : .needsSetup
            }
        }
        return status
    }

    /// The system model's availability as an engine state.
    static func state(of availability: SystemLanguageModel.Availability) -> State {
        switch availability {
        case .available: .ready(detail: nil)
        case .unavailable(.appleIntelligenceNotEnabled): .off
        case .unavailable(.modelNotReady): .needsSetup
        case .unavailable: .unavailable
        }
    }
}
