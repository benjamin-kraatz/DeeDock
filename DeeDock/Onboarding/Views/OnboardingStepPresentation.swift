import SwiftUI

/// How each tour page presents itself.
///
/// Kept apart from `OnboardingStep` so the model stays free of SwiftUI and can be tested
/// without pulling the Settings view layer into the test target.
extension OnboardingStep {
    /// Artwork for the step's tile, sharing the Settings sidebar's glyph vocabulary.
    var glyph: SettingsGlyph {
        switch self {
        case .welcome: .dock
        case .systemDock: .symbol("macwindow.on.rectangle")
        case .placement: .dock
        case .appearance: .symbol("paintbrush.pointed.fill")
        case .hiding: .symbol("sparkles")
        case .displays: .symbol("display.2")
        case .ready: .symbol("checkmark")
        }
    }

    /// Identity color for the page wash and control tint. Steps that mirror a Settings pane
    /// borrow that pane's tint so the tour and the window a person opens next agree.
    var tint: Color {
        switch self {
        case .welcome, .ready: Color(red: 0.16, green: 0.55, blue: 0.98)
        case .systemDock: Color(red: 0.94, green: 0.52, blue: 0.20)
        case .placement: SettingsCategory.position.tint
        case .appearance: SettingsCategory.appearance.tint
        case .hiding: SettingsCategory.behavior.tint
        case .displays: Color(red: 0.36, green: 0.44, blue: 0.92)
        }
    }

    /// Colors of the step's glyph tile, top to bottom.
    var tileColors: [Color] {
        switch self {
        case .welcome, .ready: SettingsCategory.position.tileColors
        case .systemDock: [Color(red: 0.99, green: 0.72, blue: 0.30), Color(red: 0.94, green: 0.44, blue: 0.13)]
        case .placement: SettingsCategory.position.tileColors
        case .appearance: SettingsCategory.appearance.tileColors
        case .hiding: SettingsCategory.behavior.tileColors
        case .displays: [Color(red: 0.55, green: 0.62, blue: 0.99), Color(red: 0.28, green: 0.32, blue: 0.88)]
        }
    }

}
