import SwiftUI

/// One open settings page, wrapped in the column every settings surface shares.
struct SettingsPageView: View {
    let page: SettingsPage
    let context: SettingsContext
    /// Set when the page is editing one display's overrides instead of the shared defaults.
    var override: SettingsOverrideContext?
    var showZone: (() -> Void)?

    var body: some View {
        SettingsPageScaffold {
            switch page.group {
            case .dock:
                DockPageContent(page: page, context: context, override: override, showZone: showZone)
            case .general:
                GeneralPageContent(page: page, context: context)
            case .features:
                FeaturesPageContent(page: page, context: context)
            }
        }
        .navigationTitle(Text(page.title))
    }
}
