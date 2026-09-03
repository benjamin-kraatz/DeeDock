import AppKit

/// Opens the SwiftUI `Settings` scene from AppKit.
///
/// `@Environment(\.openSettings)` is delivered only to views inside the `App`'s scene graph, and
/// the tour is an AppKit-hosted window, so it cannot use that action. The remaining route is the
/// action SwiftUI installs on the app menu's Settings item, for which no public symbol is
/// exposed — a limitation of the Settings scene rather than a shortcut taken here.
///
/// `open()` reports whether the action was accepted. Nothing depends on it succeeding: the
/// tour's final page also tells people about the menu-bar item and ⌘,, both of which continue
/// to work if a future macOS renames the selector.
@MainActor
enum SettingsWindowOpener {
    @discardableResult
    static func open() -> Bool {
        NSApp.activate()
        return NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
