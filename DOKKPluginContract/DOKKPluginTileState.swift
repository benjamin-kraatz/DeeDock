import Foundation

/// What a plugin's dock tile shows and does. The plugin sends it whenever it changes.
///
/// Every field is optional on the wire. A missing or unreadable field falls back to its default, so
/// a newer plugin talking to an older DOKK, or the reverse, still produces a usable tile.
nonisolated struct DOKKPluginTileState: Codable, Equatable, Sendable {
    /// The contract version the sender was built with.
    var contractVersion = DOKKPluginContract.version
    /// The tile's name in tooltips, menus, and VoiceOver. Nil uses the extension's display name.
    var title: String?
    /// The red mark on the tile. Nil shows none. DOKK hides it while the plugin is stopped.
    var badge: DOKKPluginBadge?
    /// What VoiceOver reads after the title, such as "2 new highlights". Nil reads the badge.
    var accessibilityValue: String?
    /// The size the plugin's panel content would like, in points, excluding DOKK's header.
    ///
    /// DOKK adds its 40 pt header and 10 pt pointer, then keeps the panel between 280 × 220 and
    /// 560 × 420 and inside the screen. Nil uses the largest panel. Sending a new value while the
    /// panel is open resizes it.
    var panelSize: DOKKPluginSize?
    /// What a click on the tile does.
    var primaryAction: DOKKPluginPrimaryAction = .openPanel
    /// Extra commands in the tile's menu, in order. DOKK shows at most
    /// ``DOKKPluginContract/maximumMenuItems`` and reports a choice with
    /// ``DOKKPluginHostEvent/menuItemChosen(_:)``.
    var menuItems: [DOKKPluginMenuItem] = []

    init(title: String? = nil, badge: DOKKPluginBadge? = nil, accessibilityValue: String? = nil,
         panelSize: DOKKPluginSize? = nil, primaryAction: DOKKPluginPrimaryAction = .openPanel,
         menuItems: [DOKKPluginMenuItem] = []) {
        self.title = title
        self.badge = badge
        self.accessibilityValue = accessibilityValue
        self.panelSize = panelSize
        self.primaryAction = primaryAction
        self.menuItems = menuItems
    }

    private enum CodingKeys: String, CodingKey {
        case contractVersion, title, badge, accessibilityValue, panelSize, primaryAction, menuItems
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = (try? values.decodeIfPresent(Int.self, forKey: .contractVersion)) ?? 1
        title = try? values.decodeIfPresent(String.self, forKey: .title)
        badge = try? values.decodeIfPresent(DOKKPluginBadge.self, forKey: .badge)
        accessibilityValue = try? values.decodeIfPresent(String.self, forKey: .accessibilityValue)
        panelSize = try? values.decodeIfPresent(DOKKPluginSize.self, forKey: .panelSize)
        primaryAction = (try? values.decodeIfPresent(DOKKPluginPrimaryAction.self, forKey: .primaryAction)) ?? .openPanel
        menuItems = (try? values.decodeIfPresent([DOKKPluginMenuItem].self, forKey: .menuItems)) ?? []
    }

    /// JSON for the XPC call. Encoding these plain values cannot fail.
    func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    /// Nil for data that is not a tile state at all.
    static func decode(_ data: Data) -> DOKKPluginTileState? {
        try? JSONDecoder().decode(Self.self, from: data)
    }
}

/// The red mark on a plugin tile, drawn like an app's notification badge.
nonisolated enum DOKKPluginBadge: Codable, Equatable, Sendable {
    /// A number. Zero or less shows no badge; above 99 shows "99+".
    case count(Int)
    /// A short label such as "!". DOKK draws at most ``DOKKPluginContract/maximumBadgeTextLength`` characters.
    case text(String)
    /// A dot without a label.
    case dot

    private enum CodingKeys: String, CodingKey { case kind, count, text }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "count": self = .count(try values.decode(Int.self, forKey: .count))
        case "text": self = .text(try values.decode(String.self, forKey: .text))
        case "dot": self = .dot
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unknown badge kind")
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .count(let count):
            try values.encode("count", forKey: .kind)
            try values.encode(count, forKey: .count)
        case .text(let text):
            try values.encode("text", forKey: .kind)
            try values.encode(text, forKey: .text)
        case .dot:
            try values.encode("dot", forKey: .kind)
        }
    }
}

/// A width and height in points.
nonisolated struct DOKKPluginSize: Codable, Equatable, Sendable {
    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// What a click on the plugin's tile does.
nonisolated enum DOKKPluginPrimaryAction: String, Codable, Equatable, Sendable {
    /// Opens the plugin's panel above the tile, or closes it when it is open. The default.
    case openPanel
    /// Opens the app the plugin ships in.
    case openApp

    /// Unknown actions from a newer plugin fall back to opening the panel.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .openPanel
    }
}

/// One plugin command in the tile's menu.
nonisolated struct DOKKPluginMenuItem: Codable, Equatable, Sendable, Identifiable {
    /// Stable within the plugin. DOKK sends it back when the item is chosen.
    var id: String
    /// The menu title, already localized by the plugin.
    var title: String
    /// An SF Symbol name for the item's image. Unknown names show no image.
    var systemImage: String?

    init(id: String, title: String, systemImage: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}
