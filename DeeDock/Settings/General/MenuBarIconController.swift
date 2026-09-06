import Foundation
import Observation

/// Loads and writes the menu-bar extra artwork. Missing or unknown values use the icon.
@MainActor @Observable
final class MenuBarIconController {
    private(set) var style: MenuBarIconStyle
    @ObservationIgnored private let defaults: UserDefaults
    static let key = "general.menu-bar-icon.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.key), let stored = MenuBarIconStyle(rawValue: raw) {
            style = stored
        } else {
            style = .icon
        }
    }

    func setStyle(_ style: MenuBarIconStyle) {
        guard style != self.style else { return }
        defaults.set(style.rawValue, forKey: Self.key)
        self.style = style
    }
}
