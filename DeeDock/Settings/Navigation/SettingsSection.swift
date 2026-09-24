import SwiftUI

/// A top-level sidebar entry. Selecting one shows its overview; the overview pushes `SettingsPage`s.
///
/// The fixed sections are app-scoped groupings. A `display` section edits one profile's
/// overrides and offers the same pages as `dock`, so a person moves between "for everything" and
/// "for this screen" without learning a second layout.
enum SettingsSection: Hashable, Identifiable {
    case general
    case dock
    case atmosphere
    case modes
    case extras
    case windowsFocus
    case suggestionsHistory
    /// Personality features slated for removal in 1.0.0, kept reachable but out of the way.
    case deprecated
    case display(String)

    /// What the app and the dock are; the sidebar's untitled first group.
    static let primary: [SettingsSection] = [.general, .dock, .atmosphere, .modes]
    /// Opt-in capabilities, listed under the sidebar's Features heading.
    static let featureSections: [SettingsSection] = [.extras, .windowsFocus, .suggestionsHistory]
    /// Sections that always exist, in sidebar order. Displays are inserted from the profile store.
    static let fixed: [SettingsSection] = primary + featureSections + [.deprecated]

    var id: String {
        switch self {
        case .general: "general"
        case .dock: "dock"
        case .atmosphere: "atmosphere"
        case .modes: "modes"
        case .extras: "extras"
        case .windowsFocus: "windowsFocus"
        case .suggestionsHistory: "suggestionsHistory"
        case .deprecated: "deprecated"
        case .display(let id): "display.\(id)"
        }
    }

    /// Display sections are titled by the device, so their name comes from the profile instead.
    var title: LocalizedStringResource? {
        switch self {
        case .general: .settingsGeneral
        case .dock: .settingsGroupDock
        case .atmosphere: .atmosphereTitle
        case .modes: .dockModesTitle
        case .extras: .settingsExtras
        case .windowsFocus: .settingsWindowsFocus
        case .suggestionsHistory: .settingsSuggestionsHistory
        case .deprecated: .settingsDeprecated
        case .display: nil
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .general: .settingsGeneralSummary
        case .dock: .settingsDockSummary
        case .atmosphere: .atmosphereSummary
        case .modes: .settingsModesSummary
        case .extras: .settingsExtrasSummary
        case .windowsFocus: .settingsWindowsFocusSummary
        case .suggestionsHistory: .settingsSuggestionsHistorySummary
        case .deprecated: .settingsDeprecatedSummary
        case .display: .settingsDisplaySummary
        }
    }

    var glyph: SettingsGlyph {
        switch self {
        case .general: .symbol("gearshape.fill")
        case .dock: .dock
        case .atmosphere: .symbol("sparkles")
        case .modes: .symbol("square.stack.3d.up.fill")
        case .extras: .symbol("puzzlepiece.extension.fill")
        case .windowsFocus: .symbol("macwindow.on.rectangle")
        case .suggestionsHistory: .symbol("clock.arrow.circlepath")
        case .deprecated: .symbol("archivebox.fill")
        case .display: .symbol("display")
        }
    }

    var tileColors: [Color] {
        switch self {
        case .general: [Color(red: 0.62, green: 0.65, blue: 0.70), Color(red: 0.36, green: 0.39, blue: 0.44)]
        case .dock, .display: [Color(red: 0.32, green: 0.78, blue: 1.0), Color(red: 0.06, green: 0.42, blue: 0.94)]
        case .atmosphere: [.pink, .orange]
        case .modes: [.indigo, .purple]
        case .extras: [Color(red: 1.0, green: 0.47, blue: 0.72), Color(red: 0.83, green: 0.15, blue: 0.52)]
        case .windowsFocus: [Color(red: 1.0, green: 0.58, blue: 0.34), Color(red: 0.84, green: 0.24, blue: 0.16)]
        case .suggestionsHistory: [Color(red: 0.46, green: 0.72, blue: 0.92), Color(red: 0.12, green: 0.36, blue: 0.62)]
        case .deprecated: [Color(red: 0.74, green: 0.72, blue: 0.68), Color(red: 0.50, green: 0.47, blue: 0.42)]
        }
    }

    /// Overview rows, grouped into the cards they are drawn in. Modes and Atmosphere have no
    /// sub-pages: the section is the page.
    var pageGroups: [[SettingsPage]] {
        switch self {
        case .general:
            [[.about], [.menuBar, .startup]]
        case .dock, .display:
            SettingsPage.dockGroups
        case .extras:
            [[.shelfAndTrash, .capsules, .badges],
             [.actionTiles, .quickLaunch, .soapBubbles],
             [.multipleDisplays]]
        case .windowsFocus:
            [[.windowPeek, .focusSessions], [.permissions]]
        case .suggestionsHistory:
            [[.appSuggestions, .discovery], [.localHistory, .clipboardMuseum]]
        case .deprecated:
            [SettingsPage.deprecatedPages]
        case .modes, .atmosphere:
            []
        }
    }

    /// Sections whose pages write dock preferences, so the window offers to restore them.
    var offersRestoreDefaults: Bool {
        switch self {
        case .general, .atmosphere, .modes: false
        case .dock, .display, .extras, .windowsFocus, .suggestionsHistory, .deprecated: true
        }
    }

    /// Extra search terms that belong to the section itself rather than to one of its pages.
    private var keywords: [LocalizedStringResource] {
        switch self {
        case .general:
            #if DIRECT_DISTRIBUTION
            [.settingsGeneralKeywords, .updatesAutomatic, .updatesAutomaticInstallation, .updatesIdleInstall, .updatesCheck]
            #else
            [.settingsGeneralKeywords]
            #endif
        case .dock: [.settingsAppearanceKeywords, .settingsPositionKeywords, .settingsBehaviorKeywords]
        case .extras, .windowsFocus, .suggestionsHistory: [.settingsFeatures, .settingsFeaturesKeywords]
        case .deprecated: [.settingsDeprecatedFeatureNotice]
        case .modes: [.dockModesKeywords]
        case .atmosphere: [.atmosphereSummary]
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
