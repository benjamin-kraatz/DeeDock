import Foundation

/// Requested auto-hide settings. Geometry fitting never changes these persisted values.
struct DockBehaviorSettings: Codable, Equatable {
    enum ActivationLocation: String, Codable, CaseIterable { case dockPosition, screenEdge }
    enum LengthMode: String, Codable, CaseIterable { case dockLength = "dockWidth", custom }
    /// Tint of the approach indicator. `automatic` contrasts with the wallpaper near the dock edge.
    enum ApproachColor: String, Codable, CaseIterable { case automatic, accent }
    var autoHide = false
    var activationLocation: ActivationLocation = .dockPosition
    var lengthMode: LengthMode = .dockLength
    var customLength: Double = 320
    var zoneDepth: Double = 8
    var zoneOffset: Double = 0
    var revealDelay: Double = 0.10
    var hideDelay: Double = 0.40
    var animationStyle: DockAnimationStyle = .slideFade
    var animationDuration: Double = 0.20
    /// Shows a glow at the screen edge that strengthens as the pointer nears a hidden dock's activation zone.
    var approachIndicator = false
    var approachColor: ApproachColor = .automatic

    private enum CodingKeys: String, CodingKey {
        case autoHide, activationLocation, zoneOffset, revealDelay, hideDelay, animationStyle, animationDuration
        case approachIndicator, approachColor
        case lengthMode = "widthMode", customLength = "customWidth", zoneDepth = "zoneHeight"
    }

    var isValid: Bool {
        (32...8192).contains(customLength) && (1...90).contains(zoneDepth)
            && (-4096...4096).contains(zoneOffset) && (0...2).contains(revealDelay)
            && (0...5).contains(hideDelay) && (0...1).contains(animationDuration)
            && [customLength, zoneDepth, zoneOffset, revealDelay, hideDelay, animationDuration].allSatisfy(\.isFinite)
    }

    var normalized: Self? {
        guard isValid else { return nil }
        var value = self
        value.customLength = customLength.rounded()
        value.zoneDepth = zoneDepth.rounded()
        value.zoneOffset = zoneOffset.rounded()
        value.revealDelay = (revealDelay * 20).rounded() / 20
        value.hideDelay = (hideDelay * 20).rounded() / 20
        value.animationDuration = (animationDuration * 20).rounded() / 20
        return value
    }
}

extension DockBehaviorSettings {
    /// Keys added after the first release default when absent. Original keys stay required, so a
    /// malformed document still throws instead of silently resetting.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        autoHide = try values.decode(Bool.self, forKey: .autoHide)
        activationLocation = try values.decode(ActivationLocation.self, forKey: .activationLocation)
        lengthMode = try values.decode(LengthMode.self, forKey: .lengthMode)
        customLength = try values.decode(Double.self, forKey: .customLength)
        zoneDepth = try values.decode(Double.self, forKey: .zoneDepth)
        zoneOffset = try values.decode(Double.self, forKey: .zoneOffset)
        revealDelay = try values.decode(Double.self, forKey: .revealDelay)
        hideDelay = try values.decode(Double.self, forKey: .hideDelay)
        animationStyle = try values.decode(DockAnimationStyle.self, forKey: .animationStyle)
        animationDuration = try values.decode(Double.self, forKey: .animationDuration)
        approachIndicator = try values.decodeIfPresent(Bool.self, forKey: .approachIndicator) ?? false
        approachColor = try values.decodeIfPresent(ApproachColor.self, forKey: .approachColor) ?? .automatic
    }
}
