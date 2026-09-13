import SwiftUI

/// An overview row that opens one page: glyph tile, name, optional state, disclosure chevron.
///
/// The plain button style strips the button chrome so the row reads as a line in the card rather
/// than as a control inside it, while keeping keyboard focus and Return activation.
struct SettingsLinkRow: View {
    let page: SettingsPage
    /// Trailing state such as On or Off, drawn beside the chevron the way System Settings does.
    var status: LocalizedStringResource?
    let open: (SettingsPage) -> Void
    #if DIRECT_DISTRIBUTION
    @Environment(\.appUpdater) private var updater
    #endif

    var body: some View {
        Button { open(page) } label: {
            HStack(spacing: 11) {
                SettingsIconTile(glyph: page.glyph, colors: page.tileColors, size: 24)
                    .overlay(alignment: .topTrailing) {
                        #if DIRECT_DISTRIBUTION
                        if page == .about, updater?.awareness.showsIndicators == true {
                            UpdateAwarenessBadge(diameter: 8)
                                .offset(x: 2, y: -2)
                        }
                        #endif
                    }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(page.title)
                        if page.isDeprecated {
                            DeprecatedFeatureBadge()
                        }
                    }
                    if let subtitle = page.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: SettingsMetrics.controlSpacing)
                if let status {
                    Text(status)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: Text {
        if page.isDeprecated { return Text(.settingsDeprecated) }
        return status.map { Text($0) } ?? Text(verbatim: "")
    }
}

/// A group of overview rows drawn as one card, matching the spacing of a card of controls.
struct SettingsLinkCard: View {
    /// Optional group heading.
    var title: LocalizedStringResource? = nil
    let pages: [SettingsPage]
    var status: (SettingsPage) -> LocalizedStringResource? = { _ in nil }
    let open: (SettingsPage) -> Void

    var body: some View {
        SettingsCard(title: title) {
            ForEach(pages) { page in
                SettingsLinkRow(page: page, status: status(page), open: open)
            }
        }
    }
}

#if DEBUG
#Preview("Overview rows") {
    ScrollView {
        VStack(spacing: SettingsMetrics.cardSpacing) {
            ForEach(Array(SettingsSection.extras.pageGroups.enumerated()), id: \.offset) { _, group in
                SettingsLinkCard(pages: group, status: { $0 == .badges ? .settingsStatusOff : .settingsStatusOn },
                                 open: { _ in })
            }
        }
        .padding(24)
    }
    .frame(width: 640, height: 480)
}

#Preview("Deprecated rows — German, dark") {
    SettingsLinkCard(pages: SettingsPage.deprecatedPages, open: { _ in })
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}
#endif
