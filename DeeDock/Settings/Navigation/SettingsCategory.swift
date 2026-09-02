import SwiftUI

/// One entry in the settings sidebar.
///
/// Case order is the sidebar order. Adding a pane means adding a case here, its copy to the
/// string catalog, and its content to `SettingsDetailView`; nothing else has to change.
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case appearance
    case position

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .appearance: .settingsAppearance
        case .position: .settingsPosition
        }
    }

    /// Artwork for the sidebar tile.
    var glyph: SettingsGlyph {
        switch self {
        case .appearance: .symbol("paintbrush.pointed.fill")
        case .position: .dock
        }
    }

    /// Identity color for the pane wash and its control tint.
    var tint: Color {
        switch self {
        case .appearance: Color(red: 0.52, green: 0.38, blue: 0.98)
        case .position: Color(red: 0.16, green: 0.55, blue: 0.98)
        }
    }

    /// Colors of the sidebar glyph tile, top to bottom.
    var tileColors: [Color] {
        switch self {
        case .appearance: [Color(red: 0.85, green: 0.42, blue: 0.98), Color(red: 0.42, green: 0.30, blue: 0.96)]
        case .position: [Color(red: 0.32, green: 0.78, blue: 1.0), Color(red: 0.06, green: 0.42, blue: 0.94)]
        }
    }

    /// Translatable synonyms so search finds a pane by the wording a person expects,
    /// not only by its title.
    private var keywords: LocalizedStringResource {
        switch self {
        case .appearance: .settingsAppearanceKeywords
        case .position: .settingsPositionKeywords
        }
    }

    /// Locale-aware, case- and diacritic-insensitive match. An empty query matches everything.
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [title, keywords].contains { String(localized: $0).localizedStandardContains(query) }
    }
}
