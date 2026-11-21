#if DEBUG
import SwiftUI

/// Debug builds only: tools for trying Flix Files by hand. "Show Again" lets the once-a-day
/// "Where were you?" card appear on the next open of the panel.
struct FlixDebugCard: View {
    let resetMorningCard: () -> Void
    @State private var didReset = false

    var body: some View {
        SettingsCard(title: .flixSettingsDebug, footnote: .flixSettingsDebugHelp) {
            SettingsRow(title: .flixSettingsDebugMorning, subtitle: .flixSettingsDebugMorningHelp) {
                Button {
                    resetMorningCard()
                    didReset = true
                } label: {
                    Text(didReset ? LocalizedStringResource.flixSettingsDebugMorningDone : .flixSettingsDebugMorningReset)
                }
                .controlSize(.small)
                .disabled(didReset)
            }
        }
    }
}

#Preview("Flix debug card") {
    FlixDebugCard(resetMorningCard: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}
#endif
