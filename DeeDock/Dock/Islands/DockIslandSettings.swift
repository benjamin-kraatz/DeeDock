import Foundation

/// How island glass is drawn.
enum DockIslandStyle: String, Codable, CaseIterable, Sendable {
    /// A thick frosted rim, a diagonal sheen, and a lit outer edge: the DEE-85 concept.
    case ice
    /// Today's thin dock material with a light tint wash.
    case frost
    /// A solid tinted slab, also what Reduce Transparency draws for the other styles.
    case flat

    var title: LocalizedStringResource {
        switch self {
        case .ice: .islandsStyleIce
        case .frost: .islandsStyleFrost
        case .flat: .islandsStyleFlat
        }
    }
}

/// Where an island's colour comes from when the island itself says `automatic`.
enum DockIslandTintMode: String, Codable, CaseIterable, Sendable {
    /// A fixed palette per island kind, as in the concept: purple tile, gold apps, teal running.
    case byKind
    /// The dominant hue of the icons inside each island.
    case fromIcons
    /// The system accent colour for every island.
    case accent
    /// Untinted glass.
    case none

    var title: LocalizedStringResource {
        switch self {
        case .byKind: .islandsTintModeByKind
        case .fromIcons: .islandsTintModeFromIcons
        case .accent: .islandsTintModeAccent
        case .none: .islandsTintModeNone
        }
    }
}

/// App-wide island appearance, nested in ``DockSettings``. Which pins form which island is per
/// display and lives in ``DockIslandPlan``.
struct DockIslandSettings: Codable, Equatable, Sendable {
    /// Whether docks draw islands instead of one continuous glass surface.
    var isEnabled = false
    var style: DockIslandStyle = .ice
    var tintMode: DockIslandTintMode = .byKind
    /// Multiplier on every tint alpha, 0 to 1.5.
    var tintStrength: Double = 0.7
    /// Multiplier on the lit edge and the ambient glow, 0 to 2.
    var glow: Double = 1.35
    /// Space between neighbouring islands, in points.
    var gap: Double = 12
    /// Inset from an island's glass edge to its icons, along and across the dock.
    var padding: Double = 10
    /// Width of the frosted rim, in points. Zero removes it.
    var rim: Double = 4.5
    /// Whether Ice block islands draw the lit line on the screen-edge side. The ambient glow and
    /// light leak stay; only the line and its halo go.
    var showsLamp = true

    static let defaults = DockIslandSettings()

    var isValid: Bool {
        (0...1.5).contains(tintStrength) && (0...2).contains(glow) && (4...48).contains(gap) && (4...28).contains(padding)
            && (0...8).contains(rim) && [tintStrength, glow, gap, padding, rim].allSatisfy(\.isFinite)
    }

    /// Snaps valid values to the controls' precision.
    var normalized: DockIslandSettings? {
        guard isValid else { return nil }
        var result = self
        result.tintStrength = (tintStrength * 20).rounded() / 20
        result.glow = (glow * 20).rounded() / 20
        result.gap = gap.rounded()
        result.padding = padding.rounded()
        result.rim = (rim * 2).rounded() / 2
        return result
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, style, tintMode, tintStrength, glow, gap, padding, rim, showsLamp }

    init() {}

    /// Keys added later decode to their defaults so an older document still loads.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        style = try values.decodeIfPresent(DockIslandStyle.self, forKey: .style) ?? .ice
        tintMode = try values.decodeIfPresent(DockIslandTintMode.self, forKey: .tintMode) ?? .byKind
        tintStrength = try values.decodeIfPresent(Double.self, forKey: .tintStrength) ?? 0.7
        glow = try values.decodeIfPresent(Double.self, forKey: .glow) ?? 1.35
        gap = try values.decodeIfPresent(Double.self, forKey: .gap) ?? 12
        padding = try values.decodeIfPresent(Double.self, forKey: .padding) ?? 10
        rim = try values.decodeIfPresent(Double.self, forKey: .rim) ?? 4.5
        showsLamp = try values.decodeIfPresent(Bool.self, forKey: .showsLamp) ?? true
    }
}
