import SwiftUI

/// A display-scoped settings category, available for shared defaults and display overrides.
///
/// Case order is the sidebar order. Adding a pane means adding a case here, its copy to the
/// string catalog, and its content to `SettingsDetailView`. App-wide General is a separate selection.
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case appearance
    case position
    case behavior
    case previews

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .appearance: .settingsAppearance
        case .behavior: .settingsBehavior
        case .position: .settingsPosition
        case .previews: .settingsPreviews
        }
    }

    /// Artwork for the sidebar tile.
    var glyph: SettingsGlyph {
        switch self {
        case .appearance: .symbol("paintbrush.pointed.fill")
        case .behavior: .symbol("sparkles")
        case .position: .dock
        case .previews: .symbol("macwindow.on.rectangle")
        }
    }

    /// Identity color for the pane wash and its control tint.
    var tint: Color {
        switch self {
        case .appearance: Color(red: 0.52, green: 0.38, blue: 0.98)
        case .behavior: Color(red: 0.12, green: 0.62, blue: 0.47)
        case .position: Color(red: 0.16, green: 0.55, blue: 0.98)
        case .previews: Color(red: 0.93, green: 0.46, blue: 0.22)
        }
    }

    /// Colors of the sidebar glyph tile, top to bottom.
    var tileColors: [Color] {
        switch self {
        case .appearance: [Color(red: 0.85, green: 0.42, blue: 0.98), Color(red: 0.42, green: 0.30, blue: 0.96)]
        case .behavior: [.mint, .teal]
        case .position: [Color(red: 0.32, green: 0.78, blue: 1.0), Color(red: 0.06, green: 0.42, blue: 0.94)]
        case .previews: [Color(red: 1.0, green: 0.67, blue: 0.28), Color(red: 0.91, green: 0.31, blue: 0.17)]
        }
    }

    /// Translatable synonyms so search finds a pane by the wording a person expects,
    /// not only by its title.
    private var keywords: LocalizedStringResource {
        switch self {
        case .appearance: .settingsAppearanceKeywords
        case .behavior: .settingsBehaviorKeywords
        case .position: .settingsPositionKeywords
        case .previews: .settingsPreviewsKeywords
        }
    }

    /// Locale-aware, case- and diacritic-insensitive match. An empty query matches everything.
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [title, keywords].contains { String(localized: $0).localizedStandardContains(query) }
    }
}
