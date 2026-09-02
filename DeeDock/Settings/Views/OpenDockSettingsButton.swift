import SwiftUI

/// Opening settings is an explicit focus action; passive dock interactions never call it.
struct OpenDockSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(.actionSettings) {
            NSApp.activate()
            openSettings()
        }
    }
}
