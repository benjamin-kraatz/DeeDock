import SwiftUI

/// A way into the badge history window.
struct BadgeMemorySettingsCard: View {
    let open: () -> Void
    var body: some View {
        SettingsCard(title: .badgeMemoryTitle, footnote: .badgeMemorySettingsHelp) {
            SettingsButtonRow(title: .badgeMemoryReview, action: open)
        }
    }
}
