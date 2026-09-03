import Foundation

/// Presentation metadata for the enumerated settings choices. The model itself stays free of
/// copy and iconography so persistence and geometry can be tested without the view layer.
extension DockSettings.Alignment {
    static func settingsOptions(edge: DockEdge) -> [SettingsOption<Self>] {
        [SettingsOption(value: .start, title: edge.isVertical ? .settingsAlignTop : .settingsAlignLeft,
                        symbol: edge.isVertical ? "align.vertical.top" : "align.horizontal.left"),
         SettingsOption(value: .center, title: .settingsAlignCenter,
                        symbol: edge.isVertical ? "align.vertical.center" : "align.horizontal.center"),
         SettingsOption(value: .end, title: edge.isVertical ? .settingsAlignBottom : .settingsAlignRight,
                        symbol: edge.isVertical ? "align.vertical.bottom" : "align.horizontal.right")]
    }
}

extension DockSettings.PositionReference {
    static var settingsOptions: [SettingsOption<Self>] {
        [SettingsOption(value: .usableDesktop, title: .settingsUsableDesktop, symbol: "menubar.dock.rectangle"),
         SettingsOption(value: .screenEdge, title: .settingsScreenEdge, symbol: "display")]
    }
}

extension DockEdge {
    static var settingsOptions: [SettingsOption<Self>] {
        [SettingsOption(value: .bottom, title: .settingsEdgeBottom, symbol: "rectangle.bottomthird.inset.filled"),
         SettingsOption(value: .left, title: .settingsEdgeLeft, symbol: "rectangle.leadingthird.inset.filled"),
         SettingsOption(value: .right, title: .settingsEdgeRight, symbol: "rectangle.trailingthird.inset.filled")]
    }
}
