import SwiftUI

/// The scrolling body every overview and page shares: one measured column of cards.
///
/// Keeping the column width and insets here is what makes a pushed page look like the overview it
/// came from instead of a differently padded screen. The content area stays neutral — identity
/// color lives in the sidebar and row tiles, and controls keep the system accent, the way macOS
/// does it.
struct SettingsPageScaffold<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
                content
            }
            .frame(maxWidth: SettingsMetrics.columnWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
