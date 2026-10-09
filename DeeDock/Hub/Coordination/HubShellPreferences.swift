import Foundation

/// What the Hub remembers between openings: the last tab, whether it was a window, and the
/// window's frame.
///
/// Stored as one JSON value under ``defaultsKey``, separate from `DockSettings`, because the Hub is
/// app-wide while dock settings are per display. A missing or unreadable value yields the defaults;
/// unknown keys from a newer build are ignored.
struct HubShellPreferences: Codable, Equatable {
    static let defaultsKey = "hub.shell.v1"

    /// The tab the Hub showed when it last closed. It opens on this tab again.
    var lastTab: HubTab = .apps
    /// Whether the Hub was a detached window when it last closed.
    var detached = false
    /// The detached window's last frame in AppKit screen coordinates, or nil before it was ever
    /// detached. Checked against the current displays before use.
    var detachedFrame: CGRect?

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        lastTab = (try? values.decodeIfPresent(HubTab.self, forKey: .lastTab)) ?? .apps
        detached = (try? values.decodeIfPresent(Bool.self, forKey: .detached)) ?? false
        detachedFrame = try? values.decodeIfPresent(CGRect.self, forKey: .detachedFrame)
    }

    /// Reads the stored preferences, or the defaults when none are stored or they cannot be read.
    static func load(from defaults: UserDefaults) -> HubShellPreferences {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(HubShellPreferences.self, from: data) else { return .init() }
        return value
    }

    /// Writes the preferences. Encoding a plain value cannot fail in practice; a failure keeps the
    /// previous value.
    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
