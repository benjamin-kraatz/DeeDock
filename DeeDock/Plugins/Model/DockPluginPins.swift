import Foundation

/// Which plugins have a dock tile, in tile order, and which plugins DOKK has already met.
///
/// Plugins are keyed by their extension's bundle identifier, which survives updates and
/// reinstalls. "Met" is what makes auto-pin happen once: a plugin is pinned the first time it
/// shows up enabled, and an unpinned plugin stays unpinned when it is turned off and on again.
/// Pure value logic, so previews and tests need no defaults.
struct DockPluginPins: Codable, Equatable {
    /// Pinned plugins, in the order their tiles appear in the plugin section.
    private(set) var pinned: [String] = []
    /// Every plugin DOKK has seen enabled, pinned or not.
    private(set) var seen: Set<String> = []

    func isPinned(_ id: String) -> Bool { pinned.contains(id) }

    /// Pins each plugin in `enabled` that was never seen before, at the end of the section.
    ///
    /// Pins of plugins that are currently off or uninstalled are kept, so their tiles return in
    /// place when they come back.
    /// - Returns: The plugins this call pinned, in `enabled` order.
    @discardableResult
    mutating func adopt(_ enabled: [String]) -> [String] {
        let fresh = enabled.filter { !seen.contains($0) }
        seen.formUnion(fresh)
        for id in fresh where !pinned.contains(id) { pinned.append(id) }
        return fresh
    }

    /// Pins `id` at the end of the section. Already pinned plugins keep their place.
    mutating func pin(_ id: String) {
        seen.insert(id)
        if !pinned.contains(id) { pinned.append(id) }
    }

    mutating func unpin(_ id: String) {
        pinned.removeAll { $0 == id }
    }
}

/// Reads and writes ``DockPluginPins`` in the app's defaults. App-wide: every display shows the
/// same plugin tiles, as it shows the same Shelf and Trash.
@MainActor
final class DockPluginPinStore {
    private let defaults: UserDefaults
    private static let key = "pluginPins"
    private(set) var value: DockPluginPins

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(DockPluginPins.self, from: $0) }
            ?? DockPluginPins()
    }

    /// Applies `change` and saves when it altered anything.
    func update(_ change: (inout DockPluginPins) -> Void) {
        var next = value
        change(&next)
        guard next != value else { return }
        value = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.key) }
    }
}
