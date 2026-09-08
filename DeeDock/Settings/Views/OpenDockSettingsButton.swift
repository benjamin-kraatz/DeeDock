import SwiftUI

/// Opening settings is an explicit focus action; passive dock interactions never call it.
struct OpenDockSettingsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(.actionSettings) {
            openWindow.openDockSettings()
        }
    }
}
