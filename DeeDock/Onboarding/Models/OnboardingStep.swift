import Foundation

/// One page of the first-launch tour.
///
/// Case order is presentation order; `allCases` drives the progress indicator and the
/// forward/back navigation, so inserting a case is the only change a new page needs here.
/// Adding a case also means adding its copy to the string catalog.
enum OnboardingStep: String, CaseIterable, Identifiable, Hashable {
    /// What DeeDock is and where it lives.
    case welcome
    /// Guidance for hiding the macOS Dock, the one step a person can reasonably skip.
    case systemDock
    /// Edge, alignment, offset, and distance.
    case placement
    /// Icon size, magnification, indicators, labels, and fading.
    case appearance
    /// Auto-hide, activation zones, and reveal animation.
    case hiding
    /// Independent pins and per-display overrides.
    case displays
    /// Pinning, the menu-bar item, and launching at login.
    case ready

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .welcome: .onboardingWelcomeTitle
        case .systemDock: .onboardingSystemDockTitle
        case .placement: .onboardingPlacementTitle
        case .appearance: .onboardingAppearanceTitle
        case .hiding: .onboardingHidingTitle
        case .displays: .onboardingDisplaysTitle
        case .ready: .onboardingReadyTitle
        }
    }

    /// One or two sentences under the title. Longer explanation belongs in Settings, not here.
    var summary: LocalizedStringResource {
        switch self {
        case .welcome: .onboardingWelcomeSummary
        case .systemDock: .onboardingSystemDockSummary
        case .placement: .onboardingPlacementSummary
        case .appearance: .onboardingAppearanceSummary
        case .hiding: .onboardingHidingSummary
        case .displays: .onboardingDisplaysSummary
        case .ready: .onboardingReadySummary
        }
    }

    /// Only the system-Dock guide can be passed over; the rest are a few seconds of reading.
    var isSkippable: Bool { self == .systemDock }

    /// Zero-based position, used by the progress indicator and its accessibility label.
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// The following step, or nil at the end of the tour.
    var next: Self? {
        let all = Self.allCases
        let following = all.index(after: index)
        return following < all.endIndex ? all[following] : nil
    }

    /// The preceding step, or nil at the start of the tour.
    var previous: Self? {
        let all = Self.allCases
        guard index > all.startIndex else { return nil }
        return all[all.index(before: index)]
    }
}
