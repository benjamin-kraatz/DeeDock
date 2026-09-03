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
         SettingsOption(value: .top, title: .settingsEdgeTop, symbol: "rectangle.topthird.inset.filled"),
         SettingsOption(value: .left, title: .settingsEdgeLeft, symbol: "rectangle.leadingthird.inset.filled"),
         SettingsOption(value: .right, title: .settingsEdgeRight, symbol: "rectangle.trailingthird.inset.filled")]
    }
}

extension DockEdge {
    /// Physical direction symbols shared by placement and activation controls.
    var edgeSymbol: String {
        switch self {
        case .bottom: "rectangle.bottomthird.inset.filled"
        case .top: "rectangle.topthird.inset.filled"
        case .left: "rectangle.leadingthird.inset.filled"
        case .right: "rectangle.trailingthird.inset.filled"
        }
    }
    var outwardSymbol: String {
        switch self {
        case .bottom: "arrow.down.to.line"
        case .top: "arrow.up.to.line"
        case .left: "arrow.left.to.line"
        case .right: "arrow.right.to.line"
        }
    }
    var inwardSymbol: String {
        switch self {
        case .bottom: "arrow.up"
        case .top: "arrow.down"
        case .left: "arrow.right"
        case .right: "arrow.left"
        }
    }
}

extension DockSettings.RunningIndicatorStyle {
    static var settingsOptions: [SettingsOption<Self>] {
        [SettingsOption(value: .dot, title: .settingsIndicatorDot, symbol: "circle.fill"),
         SettingsOption(value: .bar, title: .settingsIndicatorBar, symbol: "minus"),
         SettingsOption(value: .square, title: .settingsIndicatorSquare, symbol: "square.fill"),
         SettingsOption(value: .neon, title: .settingsIndicatorNeon, symbol: "lightbulb.fill"),
         SettingsOption(value: .aura, title: .settingsIndicatorAura, symbol: "sun.max.fill"),
         SettingsOption(value: .targetLock, title: .settingsIndicatorTargetLock, symbol: "viewfinder"),
         SettingsOption(value: .orbit, title: .settingsIndicatorOrbit, symbol: "circle.dotted"),
         SettingsOption(value: .stardust, title: .settingsIndicatorStardust, symbol: "sparkles"),
         SettingsOption(value: .powerBadge, title: .settingsIndicatorPowerBadge, symbol: "bolt.fill"),
         SettingsOption(value: .glitch, title: .settingsIndicatorGlitch, symbol: "waveform.path"),
         SettingsOption(value: .plasma, title: .settingsIndicatorPlasma, symbol: "waveform"),
         SettingsOption(value: .hologram, title: .settingsIndicatorHologram, symbol: "rectangle.on.rectangle"),
         SettingsOption(value: .solarFlare, title: .settingsIndicatorSolarFlare, symbol: "sun.max.fill"),
         SettingsOption(value: .prism, title: .settingsIndicatorPrism, symbol: "diamond.fill"),
         SettingsOption(value: .hidden, title: .settingsIndicatorHidden, symbol: "eye.slash")]
    }
}
