import SwiftUI

/// Compact timer decoration inside the existing, explicitly opened Focus Session panel.
struct BossFightStatusView: View {
    let session: FocusSession
    let date: Date
    let controller: FocusSessionController

    var body: some View {
        VStack(spacing: 8) {
            Label(.bossFightTitle, systemImage: "fossil.shell.fill").font(.headline)
            ProgressView(value: session.fraction(at: date)) { Text(.bossFightHealth) }
                .tint(.indigo)
                .accessibilityValue(Text(session.fraction(at: date), format: .percent.precision(.fractionLength(0))))
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
            if !controller.bossFight.party.isEmpty {
                BossFightPartyView(members: controller.bossFight.party, icons: controller.partyIcons)
            }
        }
    }
}
