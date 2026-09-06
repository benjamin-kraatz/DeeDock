import SwiftUI

/// Segmented choice for the menu-bar extra. Changing it updates the extra immediately.
struct MenuBarIconSettingsCard: View {
    let controller: MenuBarIconController

    var body: some View {
        SettingsCard(title: .menuBarIconTitle, footnote: .menuBarIconHelp) {
            SettingsStackedRow {
                SettingsOptionPicker(
                    title: .menuBarIconTitle,
                    options: MenuBarIconStyle.settingsOptions,
                    selection: Binding(get: { controller.style }, set: { controller.setStyle($0) })
                )
            }
        }
    }
}

extension MenuBarIconStyle {
    static var settingsOptions: [SettingsOption<Self>] {
        [SettingsOption(value: .icon, title: .menuBarIconIcon, symbol: "dock.rectangle"),
         SettingsOption(value: .wordmark, title: .menuBarIconWordmark, symbol: "textformat")]
    }
}

#if DEBUG
#Preview("Menu Bar Icon") {
    MenuBarIconSettingsCard(controller: MenuBarIconController(
        defaults: UserDefaults(suiteName: "MenuBarIconPreview") ?? .standard
    ))
    .padding()
    .frame(width: 560)
}

#Preview("Menu Bar Icon — wordmark, dark") {
    let defaults = UserDefaults(suiteName: "MenuBarIconPreviewWordmark") ?? .standard
    defaults.set(MenuBarIconStyle.wordmark.rawValue, forKey: MenuBarIconController.key)
    return MenuBarIconSettingsCard(controller: MenuBarIconController(defaults: defaults))
        .padding()
        .frame(width: 560)
        .preferredColorScheme(.dark)
}
#endif
