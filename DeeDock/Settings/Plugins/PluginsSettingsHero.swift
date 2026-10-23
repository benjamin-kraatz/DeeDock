import SwiftUI

/// The page's opening: the Plugins tile, its name, and what plugins are.
struct PluginsSettingsHero: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIconTile(glyph: SettingsSection.plugins.glyph, colors: SettingsSection.plugins.tileColors, size: 44)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(.pluginsSettingsTitle)
                    .font(.system(size: 20, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(.pluginsSettingsIntro)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, SettingsMetrics.captionInset)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    PluginsSettingsHero().padding().frame(width: 640)
}
#endif
