import SwiftUI

/// Opt-in collection of badge changes during focus sessions, with a way into the history window.
struct BadgeMemorySettingsCard: View {
    let memory: BadgeMemoryStore
    let open: () -> Void
    var body: some View {
        SettingsCard(title: .badgeMemoryTitle, footnote: .badgeMemorySettingsHelp) {
            SettingsToggleRow(title: .badgeMemoryCollect,
                              isOn: Binding(get: { memory.document.collectFocus }, set: memory.setCollectFocus))
                .disabled(memory.requiresReset)
            SettingsButtonRow(title: .badgeMemoryReview, action: open)
        }
    }
}
