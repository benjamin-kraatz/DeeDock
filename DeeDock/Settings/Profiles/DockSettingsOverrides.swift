import Foundation

/// The six independently inheritable settings; visibility and pins are always display-specific.
enum DockSettingField: String, CaseIterable, Codable {
    case iconSize, magnification, alignment, horizontalOffset, bottomDistance, positionReference

    var keyPath: PartialKeyPath<DockSettings> {
        switch self {
        case .iconSize: \.iconSize
        case .magnification: \.magnification
        case .alignment: \.alignment
        case .horizontalOffset: \.horizontalOffset
        case .bottomDistance: \.bottomDistance
        case .positionReference: \.positionReference
        }
    }
}

/// Nil means inherit, even when an explicit override would equal the current default.
struct DockSettingsOverrides: Codable, Equatable {
    var iconSize: Double?
    var magnification: Double?
    var alignment: DockSettings.Alignment?
    var horizontalOffset: Double?
    var bottomDistance: Double?
    var positionReference: DockSettings.PositionReference?

    func resolving(_ defaults: DockSettings) -> DockSettings {
        DockSettings(iconSize: iconSize ?? defaults.iconSize, magnification: magnification ?? defaults.magnification,
                     alignment: alignment ?? defaults.alignment, horizontalOffset: horizontalOffset ?? defaults.horizontalOffset,
                     bottomDistance: bottomDistance ?? defaults.bottomDistance, positionReference: positionReference ?? defaults.positionReference)
    }

    func contains(_ field: DockSettingField) -> Bool {
        switch field {
        case .iconSize: iconSize != nil
        case .magnification: magnification != nil
        case .alignment: alignment != nil
        case .horizontalOffset: horizontalOffset != nil
        case .bottomDistance: bottomDistance != nil
        case .positionReference: positionReference != nil
        }
    }

    mutating func set(_ field: DockSettingField, from value: DockSettings?) {
        switch field {
        case .iconSize: iconSize = value?.iconSize
        case .magnification: magnification = value?.magnification
        case .alignment: alignment = value?.alignment
        case .horizontalOffset: horizontalOffset = value?.horizontalOffset
        case .bottomDistance: bottomDistance = value?.bottomDistance
        case .positionReference: positionReference = value?.positionReference
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
