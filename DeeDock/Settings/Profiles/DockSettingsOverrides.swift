import Foundation

/// The independently inheritable settings; visibility and pins are always display-specific.
enum DockSettingField: String, CaseIterable, Codable {
    case showBackground, backgroundOpacity, fadeWhenIdle, fadeTarget, idleOpacity, idleDelay, fadeOutDuration, restoreDuration
    case appVisibility, tooltipPreset
    case iconSize, magnification, itemSpacing, runningIndicatorStyle, animateIndicators, edge, alignment, positionReference
    case alongEdgeOffset = "horizontalOffset", edgeDistance = "bottomDistance"

    case autoHide, activationLocation, zoneOffset, revealDelay, hideDelay, animationStyle, animationDuration

    case lengthMode = "widthMode", customLength = "customWidth", zoneDepth = "zoneHeight"

    var keyPath: PartialKeyPath<DockSettings> {
        switch self {
        case .showBackground: \.showBackground
        case .backgroundOpacity: \.backgroundOpacity
        case .fadeWhenIdle: \.fadeWhenIdle
        case .fadeTarget: \.fadeTarget
        case .idleOpacity: \.idleOpacity
        case .idleDelay: \.idleDelay
        case .fadeOutDuration: \.fadeOutDuration
        case .restoreDuration: \.restoreDuration
        case .appVisibility: \.appVisibility
        case .tooltipPreset: \.tooltipPreset
        case .iconSize: \.iconSize
        case .magnification: \.magnification
        case .itemSpacing: \.itemSpacing
        case .runningIndicatorStyle: \.runningIndicatorStyle
        case .animateIndicators: \.animateIndicators
        case .edge: \.edge
        case .alignment: \.alignment
        case .alongEdgeOffset: \.alongEdgeOffset
        case .edgeDistance: \.edgeDistance
        case .positionReference: \.positionReference
        case .autoHide: \.behavior.autoHide
        case .activationLocation: \.behavior.activationLocation
        case .lengthMode: \.behavior.lengthMode
        case .customLength: \.behavior.customLength
        case .zoneDepth: \.behavior.zoneDepth
        case .zoneOffset: \.behavior.zoneOffset
        case .revealDelay: \.behavior.revealDelay
        case .hideDelay: \.behavior.hideDelay
        case .animationStyle: \.behavior.animationStyle
        case .animationDuration: \.behavior.animationDuration
        }
    }
}

/// Nil means inherit, even when an explicit override would equal the current default.
struct DockSettingsOverrides: Codable, Equatable {
    var showBackground: Bool?
    var backgroundOpacity: Double?
    var fadeWhenIdle: Bool?
    var fadeTarget: DockSettings.FadeTarget?
    var idleOpacity: Double?
    var idleDelay: Double?
    var fadeOutDuration: Double?
    var restoreDuration: Double?
    var appVisibility: DockAppVisibility?
    var tooltipPreset: DockTooltipPreset?
    var iconSize: Double?
    var magnification: Double?
    var itemSpacing: Double?
    var runningIndicatorStyle: DockSettings.RunningIndicatorStyle?
    var animateIndicators: Bool?
    var edge: DockEdge?
    var alignment: DockSettings.Alignment?
    var alongEdgeOffset: Double?
    var edgeDistance: Double?
    var positionReference: DockSettings.PositionReference?

    var autoHide: Bool?
    var activationLocation: DockBehaviorSettings.ActivationLocation?
    var lengthMode: DockBehaviorSettings.LengthMode?
    var customLength: Double?
    var zoneDepth: Double?
    var zoneOffset: Double?
    var revealDelay: Double?
    var hideDelay: Double?
    var animationStyle: DockAnimationStyle?
    var animationDuration: Double?

    private enum CodingKeys: String, CodingKey {
        case showBackground, backgroundOpacity, fadeWhenIdle, fadeTarget, idleOpacity, idleDelay, fadeOutDuration, restoreDuration
        case appVisibility, tooltipPreset
        case iconSize, magnification, itemSpacing, runningIndicatorStyle, animateIndicators, edge, alignment, positionReference
        case autoHide, activationLocation, zoneOffset, revealDelay, hideDelay, animationStyle, animationDuration
        case alongEdgeOffset = "horizontalOffset", edgeDistance = "bottomDistance"
        case lengthMode = "widthMode", customLength = "customWidth", zoneDepth = "zoneHeight"
    }

    func resolving(_ defaults: DockSettings) -> DockSettings {
        var result = DockSettings(iconSize: iconSize ?? defaults.iconSize, magnification: magnification ?? defaults.magnification,
                     itemSpacing: itemSpacing ?? defaults.itemSpacing,
                     runningIndicatorStyle: runningIndicatorStyle ?? defaults.runningIndicatorStyle,
                     edge: edge ?? defaults.edge, alignment: alignment ?? defaults.alignment, alongEdgeOffset: alongEdgeOffset ?? defaults.alongEdgeOffset,
                     edgeDistance: edgeDistance ?? defaults.edgeDistance, positionReference: positionReference ?? defaults.positionReference)
        result.animateIndicators = animateIndicators ?? defaults.animateIndicators
        result.appVisibility = appVisibility ?? defaults.appVisibility
        result.tooltipPreset = tooltipPreset ?? defaults.tooltipPreset
        result.showBackground = showBackground ?? defaults.showBackground
        result.backgroundOpacity = backgroundOpacity ?? defaults.backgroundOpacity
        result.fadeWhenIdle = fadeWhenIdle ?? defaults.fadeWhenIdle
        result.fadeTarget = fadeTarget ?? defaults.fadeTarget
        result.idleOpacity = idleOpacity ?? defaults.idleOpacity
        result.idleDelay = idleDelay ?? defaults.idleDelay
        result.fadeOutDuration = fadeOutDuration ?? defaults.fadeOutDuration
        result.restoreDuration = restoreDuration ?? defaults.restoreDuration
        result.behavior.autoHide = autoHide ?? defaults.behavior.autoHide
        result.behavior.activationLocation = activationLocation ?? defaults.behavior.activationLocation
        result.behavior.lengthMode = lengthMode ?? defaults.behavior.lengthMode
        result.behavior.customLength = customLength ?? defaults.behavior.customLength
        result.behavior.zoneDepth = zoneDepth ?? defaults.behavior.zoneDepth
        result.behavior.zoneOffset = zoneOffset ?? defaults.behavior.zoneOffset
        result.behavior.revealDelay = revealDelay ?? defaults.behavior.revealDelay
        result.behavior.hideDelay = hideDelay ?? defaults.behavior.hideDelay
        result.behavior.animationStyle = animationStyle ?? defaults.behavior.animationStyle
        result.behavior.animationDuration = animationDuration ?? defaults.behavior.animationDuration
        return result
    }

    func contains(_ field: DockSettingField) -> Bool {
        switch field {
        case .showBackground: showBackground != nil
        case .backgroundOpacity: backgroundOpacity != nil
        case .fadeWhenIdle: fadeWhenIdle != nil
        case .fadeTarget: fadeTarget != nil
        case .idleOpacity: idleOpacity != nil
        case .idleDelay: idleDelay != nil
        case .fadeOutDuration: fadeOutDuration != nil
        case .restoreDuration: restoreDuration != nil
        case .appVisibility: appVisibility != nil
        case .tooltipPreset: tooltipPreset != nil
        case .iconSize: iconSize != nil
        case .magnification: magnification != nil
        case .itemSpacing: itemSpacing != nil
        case .runningIndicatorStyle: runningIndicatorStyle != nil
        case .animateIndicators: animateIndicators != nil
        case .edge: edge != nil
        case .alignment: alignment != nil
        case .alongEdgeOffset: alongEdgeOffset != nil
        case .edgeDistance: edgeDistance != nil
        case .positionReference: positionReference != nil
        case .autoHide: autoHide != nil
        case .activationLocation: activationLocation != nil
        case .lengthMode: lengthMode != nil
        case .customLength: customLength != nil
        case .zoneDepth: zoneDepth != nil
        case .zoneOffset: zoneOffset != nil
        case .revealDelay: revealDelay != nil
        case .hideDelay: hideDelay != nil
        case .animationStyle: animationStyle != nil
        case .animationDuration: animationDuration != nil
        }
    }

    mutating func set(_ field: DockSettingField, from value: DockSettings?) {
        switch field {
        case .showBackground: showBackground = value?.showBackground
        case .backgroundOpacity: backgroundOpacity = value?.backgroundOpacity
        case .fadeWhenIdle: fadeWhenIdle = value?.fadeWhenIdle
        case .fadeTarget: fadeTarget = value?.fadeTarget
        case .idleOpacity: idleOpacity = value?.idleOpacity
        case .idleDelay: idleDelay = value?.idleDelay
        case .fadeOutDuration: fadeOutDuration = value?.fadeOutDuration
        case .restoreDuration: restoreDuration = value?.restoreDuration
        case .appVisibility: appVisibility = value?.appVisibility
        case .tooltipPreset: tooltipPreset = value?.tooltipPreset
        case .iconSize: iconSize = value?.iconSize
        case .magnification: magnification = value?.magnification
        case .itemSpacing: itemSpacing = value?.itemSpacing
        case .runningIndicatorStyle: runningIndicatorStyle = value?.runningIndicatorStyle
        case .animateIndicators: animateIndicators = value?.animateIndicators
        case .edge: edge = value?.edge
        case .alignment: alignment = value?.alignment
        case .alongEdgeOffset: alongEdgeOffset = value?.alongEdgeOffset
        case .edgeDistance: edgeDistance = value?.edgeDistance
        case .positionReference: positionReference = value?.positionReference
        case .autoHide: autoHide = value?.behavior.autoHide
        case .activationLocation: activationLocation = value?.behavior.activationLocation
        case .lengthMode: lengthMode = value?.behavior.lengthMode
        case .customLength: customLength = value?.behavior.customLength
        case .zoneDepth: zoneDepth = value?.behavior.zoneDepth
        case .zoneOffset: zoneOffset = value?.behavior.zoneOffset
        case .revealDelay: revealDelay = value?.behavior.revealDelay
        case .hideDelay: hideDelay = value?.behavior.hideDelay
        case .animationStyle: animationStyle = value?.behavior.animationStyle
        case .animationDuration: animationDuration = value?.behavior.animationDuration
        }
    }
}

/// Retained across disconnects. Session-local identities are excluded from persistence.
struct DisplayProfile: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var enabled = true
    var overrides = DockSettingsOverrides()
    var isPersistent: Bool { id.hasPrefix("display.") }
}

/// The original primary display is recorded before pin migration, so interrupted migration can retry safely.
struct DisplayProfilesDocument: Codable, Equatable {
    var initialPrimaryID: String?
    var profiles: [String: DisplayProfile] = [:]
}

extension DockSettingsOverrides {
    /// Existing nullable overrides retain their decoding rules. A present edge must be a known value.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        showBackground = try values.decodeIfPresent(Bool.self, forKey: .showBackground)
        backgroundOpacity = try values.decodeIfPresent(Double.self, forKey: .backgroundOpacity)
        fadeWhenIdle = try values.decodeIfPresent(Bool.self, forKey: .fadeWhenIdle)
        fadeTarget = try values.decodeIfPresent(DockSettings.FadeTarget.self, forKey: .fadeTarget)
        idleOpacity = try values.decodeIfPresent(Double.self, forKey: .idleOpacity)
        idleDelay = try values.decodeIfPresent(Double.self, forKey: .idleDelay)
        fadeOutDuration = try values.decodeIfPresent(Double.self, forKey: .fadeOutDuration)
        restoreDuration = try values.decodeIfPresent(Double.self, forKey: .restoreDuration)
        appVisibility = try values.decodeIfPresent(DockAppVisibility.self, forKey: .appVisibility)
        tooltipPreset = try values.decodeIfPresent(DockTooltipPreset.self, forKey: .tooltipPreset)
        iconSize = try values.decodeIfPresent(Double.self, forKey: .iconSize)
        magnification = try values.decodeIfPresent(Double.self, forKey: .magnification)
        itemSpacing = try values.decodeIfPresent(Double.self, forKey: .itemSpacing)
        runningIndicatorStyle = try values.decodeIfPresent(DockSettings.RunningIndicatorStyle.self, forKey: .runningIndicatorStyle)
        animateIndicators = try values.decodeIfPresent(Bool.self, forKey: .animateIndicators)
        alignment = try values.decodeIfPresent(DockSettings.Alignment.self, forKey: .alignment)
        alongEdgeOffset = try values.decodeIfPresent(Double.self, forKey: .alongEdgeOffset)
        edgeDistance = try values.decodeIfPresent(Double.self, forKey: .edgeDistance)
        positionReference = try values.decodeIfPresent(DockSettings.PositionReference.self, forKey: .positionReference)
        autoHide = try values.decodeIfPresent(Bool.self, forKey: .autoHide)
        activationLocation = try values.decodeIfPresent(DockBehaviorSettings.ActivationLocation.self, forKey: .activationLocation)
        lengthMode = try values.decodeIfPresent(DockBehaviorSettings.LengthMode.self, forKey: .lengthMode)
        customLength = try values.decodeIfPresent(Double.self, forKey: .customLength)
        zoneDepth = try values.decodeIfPresent(Double.self, forKey: .zoneDepth)
        zoneOffset = try values.decodeIfPresent(Double.self, forKey: .zoneOffset)
        revealDelay = try values.decodeIfPresent(Double.self, forKey: .revealDelay)
        hideDelay = try values.decodeIfPresent(Double.self, forKey: .hideDelay)
        animationStyle = try values.decodeIfPresent(DockAnimationStyle.self, forKey: .animationStyle)
        animationDuration = try values.decodeIfPresent(Double.self, forKey: .animationDuration)
        edge = values.contains(.edge) ? try values.decode(DockEdge.self, forKey: .edge) : nil
    }
}
