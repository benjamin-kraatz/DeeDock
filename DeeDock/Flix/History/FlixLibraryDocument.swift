import Foundation

/// What you arranged yourself: Favorites and Smart Filters, in sidebar order.
///
/// Kept apart from the activity history so clearing or losing the history never takes your
/// arrangement with it. Missing keys decode to empty lists.
nonisolated struct FlixLibraryDocument: Codable, Equatable, Sendable {
    var favorites: [FlixFavorite] = []
    var smartFilters: [FlixSmartFilter] = []

    init(favorites: [FlixFavorite] = [], smartFilters: [FlixSmartFilter] = []) {
        self.favorites = favorites
        self.smartFilters = smartFilters
    }

    private enum CodingKeys: String, CodingKey { case favorites, smartFilters }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favorites = try container.decodeIfPresent([FlixFavorite].self, forKey: .favorites) ?? []
        smartFilters = try container.decodeIfPresent([FlixSmartFilter].self, forKey: .smartFilters) ?? []
    }
}
