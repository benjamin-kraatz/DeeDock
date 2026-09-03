import Foundation

/// Stores ordered pins in an injected preferences domain without consulting the workspace.
struct FavoritesRepository {
    private let defaults: UserDefaults
    // Keep this storage key stable when changing UI terminology or rearranging source files.
    private let key: String

    /// Selects the preferences domain. Tests supply a unique suite; production uses the app domain.
    init(defaults: UserDefaults = .standard, key: String = "dock.favorites.v1") {
        self.defaults = defaults
        self.key = key
    }

    /// Loads saved pins, evaluating and saving the seed only when no data exists.
    ///
    /// An explicitly empty collection stays empty.
    /// - Throws: A decoding or encoding error; unreadable saved bytes are not overwritten.
    func load(seed: () -> [ApplicationReference]) throws -> [ApplicationReference] {
        guard let object = defaults.object(forKey: key) else {
            let favorites = DockOrdering.unique(seed())
            try save(favorites)
            return favorites
        }
        guard let data = object as? Data else { throw CocoaError(.coderReadCorrupt) }
        return DockOrdering.unique(try JSONDecoder().decode([ApplicationReference].self, from: data))
    }

    /// Saves the first occurrence of each pin in order.
    /// - Throws: An encoding error before preferences are changed.
    func save(_ favorites: [ApplicationReference]) throws {
        defaults.set(try JSONEncoder().encode(DockOrdering.unique(favorites)), forKey: key)
    }
}
