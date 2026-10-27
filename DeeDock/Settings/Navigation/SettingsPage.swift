import SwiftUI

/// One screen of settings cards, pushed onto the detail stack from a section overview.
///
/// This mirrors how System Settings works: the sidebar picks a section, the section's overview
/// lists its pages, and a page holds the controls. Adding a page means adding a case here, its
/// copy to the string catalog, listing it in a section's `pageGroups`, and giving it content in
/// `SettingsPageView`.
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
    case privacy

    // Features — app-wide capabilities.
    case islands
    case shelfAndTrash
    case drives
    case hub
    case capsules
    case badges
    case notificationFeed
    case windowPeek
    case harbor
    case robi
    case actionTiles
    case multipleDisplays
    case permissions
    case appSuggestions
    case localHistory
    case clipboardMuseum
    case discovery
    case soapBubbles

    var id: Self { self }

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
        case .about, .softwareUpdate, .menuBar, .startup, .privacy: .general
        case .islands, .shelfAndTrash, .drives, .hub, .capsules, .badges, .notificationFeed, .windowPeek, .harbor, .robi,
             .actionTiles, .multipleDisplays, .permissions,
             .appSuggestions, .localHistory, .clipboardMuseum, .soapBubbles, .discovery: .features
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
        case .about: Self.aboutTitle
        case .softwareUpdate: .updatesSectionTitle
        case .menuBar: .menuBarIconTitle
        case .startup: .settingsStartup
        case .privacy: .settingsPrivacy
        case .islands: .islandsTitle
        case .shelfAndTrash: .settingsShelfAndTrash
        case .drives: .settingsVolumes
        case .hub: .settingsHubTitle
        case .capsules: .settingsCapsules
        case .badges: .appBadgesTitle
        case .notificationFeed: .notificationFeedName
        case .windowPeek: .windowPeekTitle
        case .harbor: .harborName
        case .robi: .robiSettingsTitle
        case .actionTiles: .actionsTitle
        case .multipleDisplays: .secondaryDockTitle
        case .appSuggestions: .launcherSuggestionsSettingsTitle
        case .localHistory: .timelineTitle
        case .clipboardMuseum: .clipboardMuseumTitle
        case .discovery: .discoveryTitle
        case .soapBubbles: .soapBubblesTitle
        case .permissions: .windowPeekPermissionsTitle
        }
    }

    /// Software Update lives in About, so the page title names both.
    private static var aboutTitle: LocalizedStringResource {
        .settingsAboutUpdates
    }

    /// Update wording that should find the About page, since that is where updates now live.
    private static var aboutKeywords: [LocalizedStringResource] {
        [.updatesSectionTitle, .updatesCheck, .updatesAutomatic, .updatesIdleInstall]
    }

    /// Brief descriptions on the Features overview, before opening a page.
    var subtitle: LocalizedStringResource? {
        switch self {
        case .islands: .islandsSubtitle
        case .shelfAndTrash: .settingsFeatureShelfSubtitle
        case .drives: .settingsFeatureDrivesSubtitle
        case .hub: .settingsFeatureHubSubtitle
        case .capsules: .settingsFeatureCapsulesSubtitle
        case .badges: .settingsFeatureBadgesSubtitle
        case .notificationFeed: .settingsFeatureNotificationFeedSubtitle
        case .windowPeek: .settingsFeaturePeekSubtitle
        case .harbor: .harborSettingsSubtitle
        case .robi: .robiSettingsSubtitle
        case .actionTiles: .settingsFeatureActionsSubtitle
        case .multipleDisplays: .settingsFeatureDisplaysSubtitle
        case .appSuggestions: .launcherSuggestionsSettingsSubtitle
        case .localHistory: .settingsFeatureTimelineSubtitle
        case .clipboardMuseum: .settingsFeatureClipboardMuseumSubtitle
        case .discovery: .discoverySettingsHelp
        case .soapBubbles: .settingsFeatureSoapBubblesSubtitle
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
        case .privacy: .symbol("hand.raised.fill")
        case .islands: .symbol("rectangle.split.3x1.fill")
        case .shelfAndTrash: .symbol("tray.full.fill")
        case .drives: .symbol("externaldrive.fill")
        case .hub: .symbol("sidebar.left")
        case .capsules: .symbol("capsule.portrait.fill")
        case .badges: .symbol("app.badge.fill")
        case .notificationFeed: .symbol("bell.badge.fill")
        case .windowPeek: .symbol("macwindow.on.rectangle")
        case .harbor: .symbol("rectangle.3.group.fill")
        case .robi: .symbol("face.smiling.inverse")
        case .actionTiles: .symbol("bolt.fill")
        case .multipleDisplays: .symbol("display.2")
        case .appSuggestions: .symbol("sparkles")
        case .localHistory: .symbol("clock.arrow.circlepath")
        case .clipboardMuseum: .symbol("building.columns.fill")
        case .discovery: .symbol("lightbulb.fill")
        case .soapBubbles: .symbol("circle.dotted")
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
        case .privacy: Color(red: 0.16, green: 0.55, blue: 0.98)
        case .islands: Color(red: 0.24, green: 0.62, blue: 0.70)
        case .shelfAndTrash: Color(red: 0.70, green: 0.50, blue: 0.28)
        case .drives: Color(red: 0.42, green: 0.48, blue: 0.58)
        case .hub: Color(red: 0.20, green: 0.48, blue: 0.96)
        case .capsules: Color(red: 0.16, green: 0.62, blue: 0.80)
        case .badges: Color(red: 0.88, green: 0.24, blue: 0.28)
        case .notificationFeed: Color(red: 0.86, green: 0.56, blue: 0.10)
        case .windowPeek: Color(red: 0.24, green: 0.50, blue: 0.94)
        case .harbor: Color(red: 0.30, green: 0.36, blue: 0.62)
        case .robi: Color(red: 0.36, green: 0.30, blue: 0.62)
        case .actionTiles: Color(red: 0.60, green: 0.34, blue: 0.90)
        case .multipleDisplays: Color(red: 0.30, green: 0.56, blue: 0.72)
        case .appSuggestions: .indigo
        case .localHistory: Color(red: 0.22, green: 0.48, blue: 0.72)
        case .clipboardMuseum: Color(red: 0.66, green: 0.52, blue: 0.30)
        case .discovery: .teal
        case .soapBubbles: Color(red: 0.38, green: 0.72, blue: 0.88)
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
        case .privacy: [Color(red: 0.42, green: 0.78, blue: 1.0), Color(red: 0.10, green: 0.44, blue: 0.92)]
        case .islands: [Color(red: 0.56, green: 0.90, blue: 0.96), Color(red: 0.16, green: 0.46, blue: 0.68)]
        case .shelfAndTrash: [Color(red: 0.86, green: 0.68, blue: 0.42), Color(red: 0.56, green: 0.38, blue: 0.18)]
        case .drives: [Color(red: 0.66, green: 0.71, blue: 0.79), Color(red: 0.30, green: 0.35, blue: 0.44)]
        case .hub: [Color(red: 0.42, green: 0.70, blue: 1.0), Color(red: 0.10, green: 0.36, blue: 0.86)]
        case .capsules: [Color(red: 0.40, green: 0.82, blue: 0.96), Color(red: 0.08, green: 0.50, blue: 0.72)]
        case .badges: [Color(red: 1.0, green: 0.44, blue: 0.42), Color(red: 0.80, green: 0.14, blue: 0.20)]
        case .notificationFeed: [Color(red: 1.0, green: 0.80, blue: 0.32), Color(red: 0.90, green: 0.52, blue: 0.06)]
        case .windowPeek: [Color(red: 0.44, green: 0.68, blue: 1.0), Color(red: 0.14, green: 0.36, blue: 0.88)]
        case .harbor: [Color(red: 0.42, green: 0.47, blue: 0.70), Color(red: 0.12, green: 0.14, blue: 0.24)]
        case .robi: [Color(red: 0.62, green: 0.54, blue: 0.92), Color(red: 0.20, green: 0.16, blue: 0.36)]
        case .actionTiles: [Color(red: 0.78, green: 0.54, blue: 1.0), Color(red: 0.48, green: 0.22, blue: 0.84)]
        case .multipleDisplays: [Color(red: 0.50, green: 0.72, blue: 0.86), Color(red: 0.20, green: 0.42, blue: 0.60)]
        case .appSuggestions: [.indigo, .purple]
        case .localHistory: [Color(red: 0.46, green: 0.72, blue: 0.92), Color(red: 0.12, green: 0.36, blue: 0.62)]
        case .clipboardMuseum: [Color(red: 0.90, green: 0.78, blue: 0.52), Color(red: 0.56, green: 0.42, blue: 0.22)]
        case .discovery: [.mint, .teal]
        case .soapBubbles: [Color(red: 0.72, green: 0.94, blue: 1.0), Color(red: 0.78, green: 0.52, blue: 0.96)]
        case .permissions: [Color(red: 1.0, green: 0.82, blue: 0.28), Color(red: 0.90, green: 0.58, blue: 0.05)]
        }
    }

    /// Translatable synonyms so search finds a page by the wording a person expects,
    /// not only by its title.
    private var keywords: LocalizedStringResource {
        switch self {
        case .appSuggestions: .launcherSuggestionsSettingsKeywords
        case .localHistory: .timelineSettingsKeywords
        case .clipboardMuseum: .clipboardMuseumSettingsKeywords
        case .discovery: .discoverySettingsHelp
        case .notificationFeed: .notificationFeedSettingsKeywords
        case .islands: .islandsSettingsKeywords
        case .harbor: .harborSettingsKeywords
        case .robi: .robiSettingsKeywords
        case .soapBubbles: .soapBubblesSettingsKeywords
        case .appearance, .appNames, .background: .settingsAppearanceKeywords
        case .position: .settingsPositionKeywords
        case .behavior, .shownApps: .settingsBehaviorKeywords
        case .about, .softwareUpdate, .menuBar, .startup, .privacy: .settingsGeneralKeywords
        case .drives: .settingsDrivesKeywords
        case .hub: .settingsHubKeywords
        case .shelfAndTrash, .capsules, .badges, .windowPeek,
             .actionTiles, .multipleDisplays, .permissions: .settingsFeaturesKeywords
        }
    }

    /// Locale-aware, case- and diacritic-insensitive match. An empty query matches everything.
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let copy: [LocalizedStringResource] = [title, keywords]
            + (self == .about || self == .softwareUpdate ? Self.aboutKeywords : [])
        return copy.contains { String(localized: $0).localizedStandardContains(query) }
    }
}
