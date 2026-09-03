import Foundation

/// Requested preferences; fitting a dock to a display never mutates these values.
struct DockSettings: Codable, Equatable {
    /// Physical along-edge anchor, independent of interface reading direction.
    enum Alignment: String, Codable, CaseIterable { case start = "left", center, end = "right" }
    /// Screen geometry used to measure placement; usableDesktop respects reserved system UI.
    enum PositionReference: String, Codable, CaseIterable {
        case usableDesktop, screenEdge

        /// Top placement uses reserved desktop bounds without overwriting the saved request.
        func resolved(for edge: DockEdge) -> Self { edge == .top ? .usableDesktop : self }
    }

    /// Requested resting size in points; the display may require a smaller effective size.
    var iconSize: Double = 48
    /// Maximum hover scale; 1 disables magnification.
    var magnification: Double = 1.4
    /// Gap between adjacent Dock items in logical points.
    var itemSpacing: Double = 4
    var edge: DockEdge = .bottom
    var alignment: Alignment = .center
    /// Signed displacement from the alignment anchor, in points; positive moves right on horizontal docks and down on side docks.
    var alongEdgeOffset: Double = 0
    /// Distance in points from the chosen reference edge to the glass outer edge.
    var edgeDistance: Double = 8
    var positionReference: PositionReference = .usableDesktop

    var behavior = DockBehaviorSettings()

    static let defaults = DockSettings()

    /// Rejects malformed persisted or transient input before it can enter geometry calculations.
    var isValid: Bool {
        behavior.isValid && (32...96).contains(iconSize) && (1...2).contains(magnification)
            && (0...24).contains(itemSpacing)
            && (-1000...1000).contains(alongEdgeOffset) && (0...300).contains(edgeDistance)
            && [iconSize, magnification, itemSpacing, alongEdgeOffset, edgeDistance].allSatisfy(\.isFinite)
    }

    /// Snaps valid values to the controls' precision. Invalid values have no normalized result.
    var normalized: DockSettings? {
        guard isValid else { return nil }
        var result = self
        result.behavior = behavior.normalized!
        result.iconSize = iconSize.rounded()
        result.magnification = (magnification * 20).rounded() / 20
        result.itemSpacing = itemSpacing.rounded()
        result.alongEdgeOffset = alongEdgeOffset.rounded()
        result.edgeDistance = edgeDistance.rounded()
        return result
    }
}


extension DockSettings {
    private enum CodingKeys: String, CodingKey {
        case iconSize, magnification, itemSpacing, edge, alignment, positionReference, behavior
        case alongEdgeOffset = "horizontalOffset"
        case edgeDistance = "bottomDistance"
    }

    /// Only an absent new key receives defaults. Existing required keys and malformed values still throw.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        iconSize = try values.decode(Double.self, forKey: .iconSize)
        magnification = try values.decode(Double.self, forKey: .magnification)
        itemSpacing = try values.decodeIfPresent(Double.self, forKey: .itemSpacing) ?? 4
        edge = values.contains(.edge) ? try values.decode(DockEdge.self, forKey: .edge) : .bottom
        alignment = try values.decode(Alignment.self, forKey: .alignment)
        alongEdgeOffset = try values.decode(Double.self, forKey: .alongEdgeOffset)
        edgeDistance = try values.decode(Double.self, forKey: .edgeDistance)
        positionReference = try values.decode(PositionReference.self, forKey: .positionReference)
        behavior = values.contains(.behavior) ? try values.decode(DockBehaviorSettings.self, forKey: .behavior) : DockBehaviorSettings()
    }
}
