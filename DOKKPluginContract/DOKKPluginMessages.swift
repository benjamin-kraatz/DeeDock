import Foundation

/// What DOKK tells a connected plugin about itself when it connects.
nonisolated struct DOKKPluginHostInfo: Codable, Equatable, Sendable {
    /// The contract version DOKK was built with.
    var contractVersion = DOKKPluginContract.version

    init() {}

    private enum CodingKeys: String, CodingKey { case contractVersion }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = (try? values.decodeIfPresent(Int.self, forKey: .contractVersion)) ?? 1
    }

    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    static func decode(_ data: Data) -> Self? { try? JSONDecoder().decode(Self.self, from: data) }
}

/// Something that happened in DOKK that the plugin may react to.
///
/// A plugin ignores events it does not know, so DOKK can add kinds without a version change.
nonisolated enum DOKKPluginHostEvent: Equatable, Sendable {
    /// The panel opened. The plugin's scene is about to appear.
    case panelOpened
    /// The panel closed. A plugin that only works while visible can pause here.
    case panelClosed
    /// The person chose one of the plugin's menu items, by ``DOKKPluginMenuItem/id``.
    case menuItemChosen(String)
    /// DOKK is about to let go of this connection: the tile was unpinned or DOKK is quitting.
    /// A plugin with no other connection open should exit soon after.
    case willDisconnect
}

nonisolated extension DOKKPluginHostEvent: Codable {
    private enum CodingKeys: String, CodingKey { case kind, id }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "panelOpened": self = .panelOpened
        case "panelClosed": self = .panelClosed
        case "menuItemChosen": self = .menuItemChosen(try values.decode(String.self, forKey: .id))
        case "willDisconnect": self = .willDisconnect
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unknown host event")
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .panelOpened: try values.encode("panelOpened", forKey: .kind)
        case .panelClosed: try values.encode("panelClosed", forKey: .kind)
        case .menuItemChosen(let id):
            try values.encode("menuItemChosen", forKey: .kind)
            try values.encode(id, forKey: .id)
        case .willDisconnect: try values.encode("willDisconnect", forKey: .kind)
        }
    }

    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    /// Nil for an event this copy of the contract does not know.
    static func decode(_ data: Data) -> Self? { try? JSONDecoder().decode(Self.self, from: data) }
}

/// Something a plugin asks DOKK to do.
///
/// DOKK ignores requests it does not know. There is deliberately no request to open the panel:
/// panels open only when the person clicks the tile.
nonisolated enum DOKKPluginRequest: String, Codable, Equatable, Sendable {
    /// Closes the plugin's panel if it is open.
    case closePanel
    /// Opens the app the plugin ships in and closes the panel.
    case openApp

    private enum CodingKeys: String, CodingKey { case kind }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(String.self, forKey: .kind)
        guard let request = Self(rawValue: kind) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unknown request")
        }
        self = request
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(rawValue, forKey: .kind)
    }

    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    static func decode(_ data: Data) -> Self? { try? JSONDecoder().decode(Self.self, from: data) }
}
