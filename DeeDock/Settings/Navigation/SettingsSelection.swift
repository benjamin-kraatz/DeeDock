import Foundation

/// Sidebar selection retains the redesigned category navigation for shared defaults.
enum SettingsSelection: Hashable {
    case defaults(SettingsCategory)
    case display(String)
}
