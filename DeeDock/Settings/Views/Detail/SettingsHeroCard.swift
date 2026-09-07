import SwiftUI

/// The card that opens a section overview: its artwork, its name, and what it covers.
struct SettingsHeroCard: View {
    let glyph: SettingsGlyph
    let colors: [Color]
    let title: Text
    let summary: LocalizedStringResource

    var body: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 16) {
                SettingsIconTile(glyph: glyph, colors: colors, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    title
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.leading)
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Hero cards") {
    ScrollView {
        VStack(spacing: SettingsMetrics.cardSpacing) {
            ForEach(SettingsSection.fixed) { section in
                SettingsHeroCard(glyph: section.glyph, colors: section.tileColors,
                                 title: Text(section.title ?? .settingsGeneral), summary: section.summary)
            }
        }
        .padding(24)
    }
    .frame(width: 620, height: 700)
}
#endif
