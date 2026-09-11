import SwiftUI

/// App-wide opt-out, independent of display profile settings and Museum capture consent.
struct DiscoverySettingsCard: View {
    let discovery: DiscoveryController

    var body: some View {
        SettingsCard(title: .discoveryTitle, footnote: .discoverySettingsHelp) {
            SettingsToggleRow(title: .discoveryEnabled,
                isOn: Binding(get: { discovery.engine.enabled }, set: discovery.setEnabled))
        }
        #if DEBUG
        SettingsCard(title: .discoveryDebugTitle, footnote: .discoveryDebugHelp) {
            ForEach(DiscoveryProposal.catalog) { proposal in
                SettingsRow(title: proposal.title) {
                    Button(.discoveryDebugShow) { discovery.debugShow(proposal) }
                }
            }
        }
        #endif
    }
}
