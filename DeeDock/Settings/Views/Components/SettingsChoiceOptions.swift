import Foundation

/// Presentation metadata for the enumerated settings choices. The model itself stays free of
/// copy and iconography so persistence and geometry can be tested without the view layer.
extension DockSettings.Alignment {
    static var settingsOptions: [SettingsOption<Self>] {
        [SettingsOption(value: .left, title: .settingsAlignLeft, symbol: "align.horizontal.left"),
         SettingsOption(value: .center, title: .settingsAlignCenter, symbol: "align.horizontal.center"),
         SettingsOption(value: .right, title: .settingsAlignRight, symbol: "align.horizontal.right")]
    }
}

extension DockSettings.PositionReference {
    static var settingsOptions: [SettingsOption<Self>] {
        [SettingsOption(value: .usableDesktop, title: .settingsUsableDesktop, symbol: "menubar.dock.rectangle"),
         SettingsOption(value: .screenEdge, title: .settingsScreenEdge, symbol: "display")]
    }
}
