import SwiftUI

/// An overview row that opens one page: glyph tile, name, disclosure chevron.
///
/// The plain button style strips the button chrome so the row reads as a line in the card rather
/// than as a control inside it, while keeping keyboard focus and Return activation.
struct SettingsLinkRow: View {
    let page: SettingsPage
    let open: (SettingsPage) -> Void

    var body: some View {
        Button { open(page) } label: {
            HStack(spacing: 11) {
                SettingsIconTile(glyph: page.glyph, colors: page.tileColors, size: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.title)
                    if let subtitle = page.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: SettingsMetrics.controlSpacing)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.vertical, SettingsMetrics.rowVerticalInset)
            .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinimumHeight, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A group of overview rows drawn as one card, matching the spacing of a card of controls.
struct SettingsLinkCard: View {
    let pages: [SettingsPage]
    let open: (SettingsPage) -> Void

    var body: some View {
        SettingsCard {
            ForEach(pages) { page in
                SettingsLinkRow(page: page, open: open)
            }
        }
    }
}

#if DEBUG
#Preview("Overview rows") {
    ScrollView {
        VStack(spacing: SettingsMetrics.cardSpacing) {
            ForEach(Array(SettingsPage.dockGroups.enumerated()), id: \.offset) { _, group in
                SettingsLinkCard(pages: group, open: { _ in })
            }
        }
        .padding(24)
    }
    .frame(width: 620, height: 420)
}
#endif
