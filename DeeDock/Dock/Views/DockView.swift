import SwiftUI

/// Connects the live dock store to presentation without starting services from a view.
///
/// Preview `DockContentView` with sample values instead of constructing a live workspace store.
struct DockView: View {
    let store: DockStore
    let interaction: DockInteraction

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        DockContentView(
            items: store.items,
            launchingIDs: store.launching,
            selectedID: store.selectedID,
            keyboardFocus: store.keyboardFocus,
            errorMessage: store.errorMessage,
            interaction: interaction,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            openApp: store.open,
            togglePin: store.toggleFavorite,
            dismissError: { store.errorMessage = nil }
        )
    }
}
