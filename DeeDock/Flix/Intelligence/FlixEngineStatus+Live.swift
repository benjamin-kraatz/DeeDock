import Foundation
import FoundationModels

extension FlixEngineStatus {
    /// What this Mac offers right now, for Settings' "What powers it" rows: Lookout from its saved
    /// settings, Apple Intelligence from the system model's availability, Robi from its key. Reads no
    /// files and starts nothing.
    @MainActor
    static func current(robi: RobiStore?) -> FlixEngineStatus {
        let lookout = LookoutSettingsRepository(defaults: .standard).loadOrDefault()
        let lookoutState: State = lookout.isActive ? .ready(detail: lookout.selection.folders.count)
            : lookout.setupCompleted ? .off : .needsSetup
        let appleState: State = switch SystemLanguageModel.default.availability {
        case .available: .ready(detail: nil)
        case .unavailable(.appleIntelligenceNotEnabled): .off
        case .unavailable(.modelNotReady): .needsSetup
        case .unavailable: .unavailable
        }
        let robiState: State = robi.map { $0.hasClaudeKey ? .ready(detail: nil) : .needsSetup } ?? .unavailable
        return FlixEngineStatus(lookout: lookoutState, appleIntelligence: appleState, robi: robiState)
    }
}
