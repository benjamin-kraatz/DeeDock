import Foundation

/// The independently inheritable settings; visibility and pins are always display-specific.
enum DockSettingField: String, CaseIterable, Codable {
    case iconSize, magnification, itemSpacing, alignment, horizontalOffset, bottomDistance, positionReference

    case autoHide, activationLocation, widthMode, customWidth, zoneHeight, zoneOffset, revealDelay, hideDelay, animationStyle, animationDuration

    var keyPath: PartialKeyPath<DockSettings> {
        switch self {
        case .iconSize: \.iconSize
        case .magnification: \.magnification
        case .itemSpacing: \.itemSpacing
        case .alignment: \.alignment
        case .horizontalOffset: \.horizontalOffset
        case .bottomDistance: \.bottomDistance
        case .positionReference: \.positionReference
        case .autoHide: \.behavior.autoHide
        case .activationLocation: \.behavior.activationLocation
        case .widthMode: \.behavior.widthMode
        case .customWidth: \.behavior.customWidth
        case .zoneHeight: \.behavior.zoneHeight
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
    var iconSize: Double?
    var magnification: Double?
    var itemSpacing: Double?
    var alignment: DockSettings.Alignment?
    var horizontalOffset: Double?
    var bottomDistance: Double?
    var positionReference: DockSettings.PositionReference?

    var autoHide: Bool?
    var activationLocation: DockBehaviorSettings.ActivationLocation?
    var widthMode: DockBehaviorSettings.WidthMode?
    var customWidth: Double?
    var zoneHeight: Double?
    var zoneOffset: Double?
    var revealDelay: Double?
    var hideDelay: Double?
    var animationStyle: DockAnimationStyle?
    var animationDuration: Double?

    func resolving(_ defaults: DockSettings) -> DockSettings {
        var result = DockSettings(iconSize: iconSize ?? defaults.iconSize, magnification: magnification ?? defaults.magnification,
                     itemSpacing: itemSpacing ?? defaults.itemSpacing,
                     alignment: alignment ?? defaults.alignment, horizontalOffset: horizontalOffset ?? defaults.horizontalOffset,
                     bottomDistance: bottomDistance ?? defaults.bottomDistance, positionReference: positionReference ?? defaults.positionReference)
        result.behavior.autoHide = autoHide ?? defaults.behavior.autoHide
        result.behavior.activationLocation = activationLocation ?? defaults.behavior.activationLocation
        result.behavior.widthMode = widthMode ?? defaults.behavior.widthMode
        result.behavior.customWidth = customWidth ?? defaults.behavior.customWidth
        result.behavior.zoneHeight = zoneHeight ?? defaults.behavior.zoneHeight
        result.behavior.zoneOffset = zoneOffset ?? defaults.behavior.zoneOffset
        result.behavior.revealDelay = revealDelay ?? defaults.behavior.revealDelay
        result.behavior.hideDelay = hideDelay ?? defaults.behavior.hideDelay
        result.behavior.animationStyle = animationStyle ?? defaults.behavior.animationStyle
        result.behavior.animationDuration = animationDuration ?? defaults.behavior.animationDuration
        return result
    }

    func contains(_ field: DockSettingField) -> Bool {
        switch field {
        case .iconSize: iconSize != nil
        case .magnification: magnification != nil
        case .itemSpacing: itemSpacing != nil
        case .alignment: alignment != nil
        case .horizontalOffset: horizontalOffset != nil
        case .bottomDistance: bottomDistance != nil
        case .positionReference: positionReference != nil
        case .autoHide: autoHide != nil
        case .activationLocation: activationLocation != nil
        case .widthMode: widthMode != nil
        case .customWidth: customWidth != nil
        case .zoneHeight: zoneHeight != nil
        case .zoneOffset: zoneOffset != nil
        case .revealDelay: revealDelay != nil
        case .hideDelay: hideDelay != nil
        case .animationStyle: animationStyle != nil
        case .animationDuration: animationDuration != nil
        }
    }

    mutating func set(_ field: DockSettingField, from value: DockSettings?) {
        switch field {
        case .iconSize: iconSize = value?.iconSize
        case .magnification: magnification = value?.magnification
        case .itemSpacing: itemSpacing = value?.itemSpacing
        case .alignment: alignment = value?.alignment
        case .horizontalOffset: horizontalOffset = value?.horizontalOffset
        case .bottomDistance: bottomDistance = value?.bottomDistance
        case .positionReference: positionReference = value?.positionReference
        case .autoHide: autoHide = value?.behavior.autoHide
        case .activationLocation: activationLocation = value?.behavior.activationLocation
        case .widthMode: widthMode = value?.behavior.widthMode
        case .customWidth: customWidth = value?.behavior.customWidth
        case .zoneHeight: zoneHeight = value?.behavior.zoneHeight
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
