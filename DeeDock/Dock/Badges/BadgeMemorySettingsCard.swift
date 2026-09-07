import SwiftUI

struct BadgeMemorySettingsCard: View {
    let memory: BadgeMemoryStore
    let open: () -> Void
    var body: some View {
        SettingsCard(title: .badgeMemoryTitle, footnote: .badgeMemorySettingsHelp) {
            SettingsToggleRow(title: .badgeMemoryCollect,
                              isOn: Binding(get: { memory.document.collectFocus }, set: memory.setCollectFocus))
                .disabled(memory.requiresReset)
            SettingsActionRow { Button(.badgeMemoryReview, action: open) }
        }
    }
}
