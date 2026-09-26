import SwiftUI

/// The scrolling body every overview and page shares: one measured column of cards, optionally
/// under a pinned strip that stays put while the column scrolls.
///
/// The studio mark sits in this backdrop, so it shows in the page margins and between cards.
/// Each card paints the same mark on its own fill.
///
/// Keeping the column width and insets here is what makes a pushed page look like the overview it
/// came from instead of a differently padded screen. The content area stays neutral — identity
/// color lives in the sidebar and row tiles, and controls keep the system accent, the way macOS
/// does it.
struct SettingsPageScaffold<Pinned: View, Content: View>: View {
    private let pinned: Pinned
    private let content: Content
    private let hasPinned: Bool

    /// A page whose `pinned` view, such as a live preview, stays visible above the scrolling cards.
    init(@ViewBuilder pinned: () -> Pinned, @ViewBuilder content: () -> Content) {
        self.pinned = pinned()
        self.content = content()
        hasPinned = true
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasPinned {
                pinned
                    .frame(maxWidth: SettingsMetrics.columnWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, SettingsMetrics.pageInset)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
                    content
                }
                .frame(maxWidth: SettingsMetrics.columnWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SettingsMetrics.pageInset)
                .padding(.top, hasPinned ? 18 : 20)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { StudioMarkUnderlay() }
    }
}

extension SettingsPageScaffold where Pinned == EmptyView {
    /// A page that scrolls as one column, with nothing pinned above it.
    init(@ViewBuilder content: () -> Content) {
        pinned = EmptyView()
        self.content = content()
        hasPinned = false
    }
}
