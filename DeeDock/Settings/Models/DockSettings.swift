import Foundation

/// Requested preferences; fitting a dock to a display never mutates these values.
struct DockSettings: Codable, Equatable {
    /// Physical horizontal anchor, independent of interface reading direction.
    enum Alignment: String, Codable, CaseIterable { case left, center, right }
    /// Screen geometry used to measure placement; usableDesktop respects reserved system UI.
    enum PositionReference: String, Codable, CaseIterable { case usableDesktop, screenEdge }

    /// Requested resting size in points; the display may require a smaller effective size.
    var iconSize: Double = 48
    /// Maximum hover scale; 1 disables magnification.
    var magnification: Double = 1.4
    var alignment: Alignment = .center
    /// Signed displacement from the alignment anchor, in points; positive moves right.
    var horizontalOffset: Double = 0
    /// Distance in points from the reference frame bottom to the glass bottom.
    var bottomDistance: Double = 8
    var positionReference: PositionReference = .usableDesktop

    static let defaults = DockSettings()

    /// Rejects malformed persisted or transient input before it can enter geometry calculations.
    var isValid: Bool {
        (32...96).contains(iconSize) && (1...2).contains(magnification)
            && (-1000...1000).contains(horizontalOffset) && (0...300).contains(bottomDistance)
            && [iconSize, magnification, horizontalOffset, bottomDistance].allSatisfy(\.isFinite)
    }

    /// Snaps valid values to the controls' precision. Invalid values have no normalized result.
    var normalized: DockSettings? {
        guard isValid else { return nil }
        var result = self
        result.iconSize = iconSize.rounded()
        result.magnification = (magnification * 20).rounded() / 20
        result.horizontalOffset = horizontalOffset.rounded()
        result.bottomDistance = bottomDistance.rounded()
        return result
    }
}
