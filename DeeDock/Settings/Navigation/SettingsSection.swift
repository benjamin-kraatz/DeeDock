import SwiftUI

/// A top-level sidebar entry. Selecting one shows its overview; the overview pushes `SettingsPage`s.
///
/// The four fixed sections are app-scoped groupings. A `display` section edits one profile's
/// overrides and offers the same pages as `dock`, so a person moves between "for everything" and
/// "for this screen" without learning a second layout.
enum SettingsSection: Hashable, Identifiable {
    case general
    case dock
    case features
    case modes
    case display(String)

    /// Sections that always exist, in sidebar order. Displays are appended from the profile store.
    static let fixed: [SettingsSection] = [.general, .dock, .features, .modes]

    var id: String {
        switch self {
        case .general: "general"
        case .dock: "dock"
        case .features: "features"
        case .modes: "modes"
        case .display(let id): "display.\(id)"
        }
    }

    /// Display sections are titled by the device, so their name comes from the profile instead.
    var title: LocalizedStringResource? {
        switch self {
        case .general: .settingsGeneral
        case .dock: .settingsGroupDock
        case .features: .settingsFeatures
        case .modes: .dockModesTitle
        case .display: nil
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .general: .settingsGeneralSummary
        case .dock: .settingsDockSummary
        case .features: .settingsFeaturesSummary
        case .modes: .settingsModesSummary
        case .display: .settingsDisplaySummary
        }
    }

    var glyph: SettingsGlyph {
        switch self {
        case .general: .symbol("gearshape.fill")
        case .dock: .dock
        case .features: .symbol("puzzlepiece.extension.fill")
        case .modes: .symbol("square.stack.3d.up.fill")
        case .display: .symbol("display")
        }
    }


    var tileColors: [Color] {
        switch self {
        case .general: [Color(red: 0.62, green: 0.65, blue: 0.70), Color(red: 0.36, green: 0.39, blue: 0.44)]
        case .dock, .display: [Color(red: 0.32, green: 0.78, blue: 1.0), Color(red: 0.06, green: 0.42, blue: 0.94)]
        case .features: [Color(red: 1.0, green: 0.47, blue: 0.72), Color(red: 0.83, green: 0.15, blue: 0.52)]
        case .modes: [.indigo, .purple]
        }
    }

    /// Overview rows, grouped into the cards they are drawn in. Modes has no sub-pages: its
    /// section is the page.
    var pageGroups: [[SettingsPage]] {
        switch self {
        case .general:
            #if DIRECT_DISTRIBUTION
            [[.about, .softwareUpdate], [.menuBar, .startup]]
            #else
            [[.about], [.menuBar, .startup]]
            #endif
        case .dock, .display:
            SettingsPage.dockGroups
        case .features:
            [[.shelfAndTrash, .capsules, .badges],
             [.windowPeek, .focusSessions, .actionTiles, .appSuggestions],
             [.multipleDisplays, .permissions]]
        case .modes:
            []
        }
    }

    /// Extra search terms that belong to the section itself rather than to one of its pages.
    private var keywords: [LocalizedStringResource] {
        switch self {
        case .general:
            #if DIRECT_DISTRIBUTION
            [.settingsGeneralKeywords, .updatesAutomatic, .updatesAutomaticInstallation, .updatesCheck]
            #else
            [.settingsGeneralKeywords]
            #endif
        case .dock: [.settingsAppearanceKeywords, .settingsPositionKeywords, .settingsBehaviorKeywords]
        case .features: [.settingsFeaturesKeywords]
        case .modes: [.dockModesKeywords]
        case .display: []
        }
    }

    /// A section matches when its own copy matches, or when any page it offers does, so searching
    /// for a control that lives two levels down still surfaces the way to reach it.
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let own = ([title].compactMap(\.self) + [summary] + keywords)
        if own.contains(where: { String(localized: $0).localizedStandardContains(query) }) { return true }
        return pageGroups.flatMap(\.self).contains { $0.matches(query) }
    }
}
