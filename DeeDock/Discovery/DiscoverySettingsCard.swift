import SwiftUI

/// App-wide opt-out, independent of display profile settings and Museum capture consent.
struct DiscoverySettingsCard: View {
    let discovery: DiscoveryController

    var body: some View {
        SettingsCard(title: .discoveryTitle, footnote: .discoverySettingsHelp) {
            SettingsToggleRow(title: .discoveryEnabled,
                isOn: Binding(get: { discovery.engine.enabled }, set: discovery.setEnabled))
        }
    }
}
