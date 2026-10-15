import Foundation

/// Lookout's five onboarding steps, in order (the approved mockup's `obHTML`).
nonisolated enum LookoutSetupStep: Int, CaseIterable, Comparable, Sendable {
    /// What Lookout does, three examples and how it handles data.
    case welcome
    /// Which folders it reads, with an estimate for each.
    case folders
    /// macOS's Files and Folders prompt for each protected folder, asked in context.
    case access
    /// The model download (865 MB), and whether reading may run on battery.
    case download
    /// The first pass reading the files. Setup is complete from here on.
    case firstPass

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The step's token for analytics.
    var analytics: AnalyticsLookoutSetupStep {
        switch self {
        case .welcome: .welcome
        case .folders: .folders
        case .access: .access
        case .download: .download
        case .firstPass: .firstPass
        }
    }
}

/// Which way the last step change went, so the new step slides in from that side.
nonisolated enum LookoutSetupDirection: Sendable, Equatable {
    case forward, back

    /// +1 when moving on, −1 when going back.
    var sign: CGFloat { self == .forward ? 1 : -1 }
}
