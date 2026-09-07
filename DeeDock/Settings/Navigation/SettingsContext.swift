import SwiftUI

/// Everything the settings surfaces need, gathered once so an overview or a page takes one value.
///
/// The detail column pushes pages that each need a different subset of the app's controllers.
/// Passing them individually made every intermediate view a parameter list; this keeps the
/// plumbing in one place and lets a page reach only for what it uses.
@MainActor
struct SettingsContext {
    let store: DockSettingsStore
    let profiles: DisplayProfilesStore
    let loginItems: LoginItemController
    let menuBarIcon: MenuBarIconController
    let windowAccess: WindowAccessController
    let screenCapture: ScreenCaptureAccessController
    var coordinator: DockCoordinator?

    /// Bindings for the shared defaults, or for one display when `override` is given.
    func source(_ override: SettingsOverrideContext? = nil) -> SettingsValueSource {
        SettingsValueSource(store: store, profiles: profiles, context: override)
    }

    /// Unreadable preferences must not be quietly replaced by an edit, so persistent controls stay
    /// frozen until the person chooses to reset them.
    func isLocked(_ override: SettingsOverrideContext? = nil) -> Bool {
        store.requiresReset || override?.profiles.requiresReset == true
    }

    /// The failure worth showing under the current scope, most specific first.
    func errorMessage(_ override: SettingsOverrideContext?) -> LocalizedStringResource? {
        if let override { return profiles.errorMessage ?? profiles.modes.errorMessage ?? profiles.pinErrors[override.id] }
        return profiles.errorMessage ?? profiles.modes.errorMessage ?? store.errorMessage
    }
}
