import Foundation

/// App-wide General is separate from display-scoped categories and profile selection.
enum SettingsSelection: Hashable {
    case general
    case modes
    case defaults(SettingsCategory)
    case display(String)

    /// Localized synonyms let users find General by login and startup terminology.
    static func generalMatches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [LocalizedStringResource.settingsGeneral, .settingsGeneralKeywords]
            .contains { String(localized: $0).localizedStandardContains(query) }
    }


    static func modesMatches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [LocalizedStringResource.dockModesTitle, .dockModesKeywords]
            .contains { String(localized: $0).localizedStandardContains(query) }
    }
}
