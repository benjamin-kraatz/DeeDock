import SwiftUI

/// One screen of settings cards, pushed onto the detail stack from a section overview.
///
/// This mirrors how System Settings works: the sidebar picks a section, the section's overview
/// lists its pages, and a page holds the controls. Adding a page means adding a case here, its
/// copy to the string catalog, listing it in a section's `pageGroups`, and giving it content in
/// `SettingsPageView`. Deprecated personality pages also belong in `deprecatedPages`.
///
/// The `dock` cases are the display-scopable ones: every control they show writes through a
/// `SettingsOverrideContext` when a display profile is being edited, so the same page serves both
/// the shared defaults and a single display.
enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    // Dock — shared defaults, and overridable per display.
    case appearance
    case appNames
    case background
    case position
    case behavior
    case shownApps

    // General — app-wide, never display-scoped.
    case about
    case softwareUpdate
    case menuBar
    case startup

    // Features — app-wide capabilities.
    case shelfAndTrash
    case capsules
    case badges
    case windowPeek
    case focusSessions
    case patchBay
    case actionTiles
    case multipleDisplays
    case permissions
    case appSuggestions
    case localHistory
    case pinWeather
    case clipboardMuseum
    case magneticEdges
    case sims
    case discovery
    case soapBubbles
    case focusBreathing
    case focusDebt
    case quarantine

    var id: Self { self }

    /// Personality features slated for removal in 1.0.0. Launch turns their enable flags off.
    static let deprecatedPages: [SettingsPage] = [
        .sims, .focusBreathing, .focusDebt, .pinWeather, .quarantine, .patchBay
    ]

    /// True for the Features overview's bottom group and the shared 1.0.0 removal notice.
    var isDeprecated: Bool { Self.deprecatedPages.contains(self) }

    /// Which family of content a page belongs to, so the detail view can hand it to the one view
    /// that knows how to build it.
    enum Group {
        case dock
        case general
        case features
    }

    var group: Group {
        switch self {
        case .appearance, .appNames, .background, .position, .behavior, .shownApps: .dock
        case .about, .softwareUpdate, .menuBar, .startup: .general
        case .shelfAndTrash, .capsules, .badges, .windowPeek,
             .focusSessions, .focusBreathing, .focusDebt, .patchBay, .actionTiles, .multipleDisplays, .permissions,
             .appSuggestions, .localHistory, .pinWeather, .clipboardMuseum, .magneticEdges, .sims, .soapBubbles,
             .discovery, .quarantine: .features
        }
    }

    /// Dock pages in overview order, split into the groups drawn as separate cards.
    static let dockGroups: [[SettingsPage]] = [
        [.appearance, .appNames, .background],
        [.position, .behavior],
        [.shownApps],
    ]

    /// Every page a display profile can override.
    static var dockPages: [SettingsPage] { dockGroups.flatMap(\.self) }

    var title: LocalizedStringResource {
        switch self {
        case .appearance: .settingsAppearance
        case .appNames: .settingsAppNames
        case .background: .settingsBackgroundAndFading
        case .position: .settingsPosition
        case .behavior: .settingsBehavior
        case .shownApps: .settingsAppVisibility
        case .about: .settingsAbout
        case .softwareUpdate: .updatesSectionTitle
        case .menuBar: .menuBarIconTitle
        case .startup: .settingsStartup
        case .shelfAndTrash: .settingsShelfAndTrash
        case .capsules: .settingsCapsules
        case .badges: .appBadgesTitle
        case .windowPeek: .windowPeekTitle
        case .focusSessions: .focusTitle
        case .focusBreathing: .focusBreathingTitle
        case .focusDebt: .focusDebtTitle
        case .patchBay: .patchBayTitle
        case .actionTiles: .actionsTitle
        case .multipleDisplays: .secondaryDockTitle
        case .appSuggestions: .launcherSuggestionsSettingsTitle
        case .localHistory: .timelineTitle
        case .pinWeather: .pinWeatherTitle
        case .clipboardMuseum: .clipboardMuseumTitle
        case .magneticEdges: .settingsMagneticEdges
        case .sims: .simsTitle
        case .discovery: .discoveryTitle
        case .soapBubbles: .soapBubblesTitle
        case .quarantine: .quarantineTitle
        case .permissions: .windowPeekPermissionsTitle
        }
    }

    /// Brief descriptions on the Features overview, before opening a page.
    var subtitle: LocalizedStringResource? {
        switch self {
        case .shelfAndTrash: .settingsFeatureShelfSubtitle
        case .capsules: .settingsFeatureCapsulesSubtitle
        case .badges: .settingsFeatureBadgesSubtitle
        case .windowPeek: .settingsFeaturePeekSubtitle
        case .focusSessions: .settingsFeatureFocusSubtitle
        case .focusBreathing: .settingsFeatureFocusBreathingSubtitle
        case .focusDebt: .settingsFeatureFocusDebtSubtitle
        case .patchBay: .patchBaySubtitle
        case .actionTiles: .settingsFeatureActionsSubtitle
        case .multipleDisplays: .settingsFeatureDisplaysSubtitle
        case .appSuggestions: .launcherSuggestionsSettingsSubtitle
        case .localHistory: .settingsFeatureTimelineSubtitle
        case .pinWeather: .settingsFeaturePinWeatherSubtitle
        case .clipboardMuseum: .settingsFeatureClipboardMuseumSubtitle
        case .magneticEdges: .settingsFeatureMagneticSubtitle
        case .sims: .settingsFeatureSimsSubtitle
        case .discovery: .discoverySettingsHelp
        case .soapBubbles: .settingsFeatureSoapBubblesSubtitle
        case .quarantine: .settingsFeatureQuarantineSubtitle
        case .permissions: .settingsFeaturePermissionsSubtitle
        default: nil
        }
    }

    /// Artwork for the overview row and, where the page owns a sidebar entry, its tile.
    var glyph: SettingsGlyph {
        switch self {
        case .appearance: .symbol("paintbrush.pointed.fill")
        case .appNames: .symbol("character.bubble.fill")
        case .background: .symbol("circle.lefthalf.filled")
        case .position: .dock
        case .behavior: .symbol("sparkles")
        case .shownApps: .symbol("square.grid.2x2.fill")
        case .about: .symbol("info")
        case .softwareUpdate: .symbol("arrow.down.circle.fill")
        case .menuBar: .symbol("menubar.rectangle")
        case .startup: .symbol("power")
        case .shelfAndTrash: .symbol("tray.full.fill")
        case .capsules: .symbol("capsule.portrait.fill")
        case .badges: .symbol("app.badge.fill")
        case .windowPeek: .symbol("macwindow.on.rectangle")
        case .focusSessions: .symbol("timer")
        case .focusBreathing: .symbol("wind")
        case .focusDebt: .symbol("hourglass")
        case .patchBay: .symbol("point.3.connected.trianglepath.dotted")
        case .actionTiles: .symbol("bolt.fill")
        case .multipleDisplays: .symbol("display.2")
        case .appSuggestions: .symbol("sparkles")
        case .localHistory: .symbol("clock.arrow.circlepath")
        case .pinWeather: .symbol("leaf.fill")
        case .clipboardMuseum: .symbol("building.columns.fill")
        case .magneticEdges: .symbol("arrow.up.and.down.and.arrow.left.and.right")
        case .sims: .symbol("heart.fill")
        case .discovery: .symbol("lightbulb.fill")
        case .soapBubbles: .symbol("circle.dotted")
        case .quarantine: .symbol("seal.fill")
        case .permissions: .symbol("lock.fill")
        }
    }

    /// Identity color for the page wash and its control tint.
    var tint: Color {
        switch self {
        case .appearance: Color(red: 0.52, green: 0.38, blue: 0.98)
        case .appNames: Color(red: 0.10, green: 0.58, blue: 0.72)
        case .background: Color(red: 0.36, green: 0.36, blue: 0.86)
        case .position: Color(red: 0.16, green: 0.55, blue: 0.98)
        case .behavior: Color(red: 0.12, green: 0.62, blue: 0.47)
        case .shownApps: Color(red: 0.86, green: 0.48, blue: 0.10)
        case .about, .menuBar: Color(red: 0.42, green: 0.45, blue: 0.50)
        case .softwareUpdate: Color(red: 0.16, green: 0.55, blue: 0.98)
        case .startup: Color(red: 0.20, green: 0.66, blue: 0.32)
        case .shelfAndTrash: Color(red: 0.70, green: 0.50, blue: 0.28)
        case .capsules: Color(red: 0.16, green: 0.62, blue: 0.80)
        case .badges: Color(red: 0.88, green: 0.24, blue: 0.28)
        case .windowPeek: Color(red: 0.24, green: 0.50, blue: 0.94)
        case .focusSessions: Color(red: 0.92, green: 0.38, blue: 0.24)
        case .focusBreathing: Color(red: 0.18, green: 0.62, blue: 0.58)
        case .focusDebt: Color(red: 0.72, green: 0.48, blue: 0.22)
        case .patchBay: .teal
        case .actionTiles: Color(red: 0.60, green: 0.34, blue: 0.90)
        case .multipleDisplays: Color(red: 0.30, green: 0.56, blue: 0.72)
        case .appSuggestions: .indigo
        case .localHistory: Color(red: 0.22, green: 0.48, blue: 0.72)
        case .pinWeather: Color(red: 0.62, green: 0.40, blue: 0.24)
        case .clipboardMuseum: Color(red: 0.66, green: 0.52, blue: 0.30)
        case .magneticEdges: Color(red: 0.18, green: 0.58, blue: 0.78)
        case .sims: Color(red: 0.92, green: 0.42, blue: 0.58)
        case .discovery: .teal
        case .soapBubbles: Color(red: 0.38, green: 0.72, blue: 0.88)
        case .quarantine: Color(red: 0.78, green: 0.27, blue: 0.16)
        case .permissions: Color(red: 0.90, green: 0.68, blue: 0.10)
        }
    }

    /// Colors of the row's glyph tile, top to bottom.
    var tileColors: [Color] {
        switch self {
        case .appearance: [Color(red: 0.85, green: 0.42, blue: 0.98), Color(red: 0.42, green: 0.30, blue: 0.96)]
        case .appNames: [Color(red: 0.30, green: 0.80, blue: 0.88), Color(red: 0.05, green: 0.50, blue: 0.68)]
        case .background: [Color(red: 0.58, green: 0.58, blue: 0.96), Color(red: 0.26, green: 0.24, blue: 0.76)]
        case .position: [Color(red: 0.32, green: 0.78, blue: 1.0), Color(red: 0.06, green: 0.42, blue: 0.94)]
        case .behavior: [.mint, .teal]
        case .shownApps: [Color(red: 1.0, green: 0.70, blue: 0.24), Color(red: 0.86, green: 0.40, blue: 0.05)]
        case .about, .menuBar: [Color(red: 0.62, green: 0.65, blue: 0.70), Color(red: 0.36, green: 0.39, blue: 0.44)]
        case .softwareUpdate: [Color(red: 0.42, green: 0.78, blue: 1.0), Color(red: 0.10, green: 0.44, blue: 0.92)]
        case .startup: [Color(red: 0.44, green: 0.84, blue: 0.46), Color(red: 0.10, green: 0.56, blue: 0.24)]
        case .shelfAndTrash: [Color(red: 0.86, green: 0.68, blue: 0.42), Color(red: 0.56, green: 0.38, blue: 0.18)]
        case .capsules: [Color(red: 0.40, green: 0.82, blue: 0.96), Color(red: 0.08, green: 0.50, blue: 0.72)]
        case .badges: [Color(red: 1.0, green: 0.44, blue: 0.42), Color(red: 0.80, green: 0.14, blue: 0.20)]
        case .windowPeek: [Color(red: 0.44, green: 0.68, blue: 1.0), Color(red: 0.14, green: 0.36, blue: 0.88)]
        case .focusSessions: [Color(red: 1.0, green: 0.58, blue: 0.34), Color(red: 0.84, green: 0.24, blue: 0.16)]
        case .focusBreathing: [Color(red: 0.46, green: 0.86, blue: 0.80), Color(red: 0.10, green: 0.50, blue: 0.48)]
        case .focusDebt: [Color(red: 0.92, green: 0.70, blue: 0.38), Color(red: 0.58, green: 0.36, blue: 0.14)]
        case .patchBay: [.mint, .teal]
        case .actionTiles: [Color(red: 0.78, green: 0.54, blue: 1.0), Color(red: 0.48, green: 0.22, blue: 0.84)]
        case .multipleDisplays: [Color(red: 0.50, green: 0.72, blue: 0.86), Color(red: 0.20, green: 0.42, blue: 0.60)]
        case .appSuggestions: [.indigo, .purple]
        case .localHistory: [Color(red: 0.46, green: 0.72, blue: 0.92), Color(red: 0.12, green: 0.36, blue: 0.62)]
        case .pinWeather: [Color(red: 0.86, green: 0.62, blue: 0.38), Color(red: 0.48, green: 0.28, blue: 0.16)]
        case .clipboardMuseum: [Color(red: 0.90, green: 0.78, blue: 0.52), Color(red: 0.56, green: 0.42, blue: 0.22)]
        case .magneticEdges: [Color(red: 0.42, green: 0.84, blue: 0.96), Color(red: 0.10, green: 0.46, blue: 0.72)]
        case .sims: [Color(red: 1.0, green: 0.62, blue: 0.72), Color(red: 0.86, green: 0.22, blue: 0.46)]
        case .discovery: [.mint, .teal]
        case .soapBubbles: [Color(red: 0.72, green: 0.94, blue: 1.0), Color(red: 0.78, green: 0.52, blue: 0.96)]
        case .quarantine: [Color(red: 0.92, green: 0.46, blue: 0.34), Color(red: 0.62, green: 0.18, blue: 0.12)]
        case .permissions: [Color(red: 1.0, green: 0.82, blue: 0.28), Color(red: 0.90, green: 0.58, blue: 0.05)]
        }
    }

    /// Translatable synonyms so search finds a page by the wording a person expects,
    /// not only by its title.
    private var keywords: LocalizedStringResource {
        switch self {
        case .patchBay: .patchBayHelp
        case .appSuggestions: .launcherSuggestionsSettingsKeywords
        case .localHistory: .timelineSettingsKeywords
        case .pinWeather: .pinWeatherSettingsKeywords
        case .clipboardMuseum: .clipboardMuseumSettingsKeywords
        case .magneticEdges: .settingsMagneticEdgesKeywords
        case .sims: .simsSettingsKeywords
        case .discovery: .discoverySettingsHelp
        case .soapBubbles: .soapBubblesSettingsKeywords
        case .focusBreathing: .focusBreathingHelp
        case .focusDebt: .focusDebtHelp
        case .quarantine: .quarantineSettingsHelp
        case .appearance, .appNames, .background: .settingsAppearanceKeywords
        case .position: .settingsPositionKeywords
        case .behavior, .shownApps: .settingsBehaviorKeywords
        case .about, .softwareUpdate, .menuBar, .startup: .settingsGeneralKeywords
        case .shelfAndTrash, .capsules, .badges, .windowPeek,
             .focusSessions, .actionTiles, .multipleDisplays, .permissions: .settingsFeaturesKeywords
        }
    }

    /// Locale-aware, case- and diacritic-insensitive match. An empty query matches everything.
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let copy: [LocalizedStringResource] = [title, keywords]
            + (isDeprecated ? [.settingsDeprecated, .settingsDeprecatedFeatureNotice] : [])
            + (self == .softwareUpdate ? [.updatesIdleInstall] : [])
        return copy.contains { String(localized: $0).localizedStandardContains(query) }
    }
}
