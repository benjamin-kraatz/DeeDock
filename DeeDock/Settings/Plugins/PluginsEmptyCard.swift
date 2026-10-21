import SwiftUI

/// What the page shows before any plugin is installed: what to expect, and Manage Plugins… in case
/// the system window knows of one DOKK has not counted yet.
struct PluginsEmptyCard: View {
    let manage: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 46, height: 46)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 13, style: .continuous))
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text(.pluginsEmptyTitle)
                .font(.system(size: 14, weight: .semibold))
            Text(.pluginsEmptyDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: manage) { Text(.pluginsManage) }
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 24)
        .background(.background.secondary, in: shape)
        .overlay(shape.strokeBorder(.separator.opacity(colorScheme == .dark ? 0.6 : 0.4), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview {
    PluginsEmptyCard {}.padding(24).frame(width: 640)
}
#endif
