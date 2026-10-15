import Foundation

nonisolated extension LookoutProblemReason {
    /// Why files were skipped or not read, in a few words, beside their count in the progress card
    /// (`LookoutProgressDisplay.problems`, which `LookoutProgressTracker` fills in with these).
    var title: LocalizedStringResource {
        switch self {
        case .tooSmall: .lookoutProblemTooSmall
        case .tooLarge: .lookoutProblemTooLarge
        case .passwordProtected: .lookoutProblemPasswordProtected
        case .noText: .lookoutProblemNoText
        case .notDownloaded: .lookoutProblemNotDownloaded
        case .excluded: .lookoutProblemExcluded
        case .unreadable: .lookoutProblemUnreadable
        case .other: .lookoutProblemOther
        }
    }
}
