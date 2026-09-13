import SwiftUI

/// Capsule label used on Features overview rows for personality features slated for removal.
struct DeprecatedFeatureBadge: View {
    var body: some View {
        Text(.settingsDeprecated)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.16), in: Capsule())
            .accessibilityHidden(true)
    }
}

/// Warning shown at the top of every deprecated feature's settings page.
///
/// One shared view so the 1.0.0 removal copy stays identical for Sims, Focus breathing,
/// Focus debt, Pin weather, Quarantine stamp, and Patch bay.
struct DeprecatedFeatureNotice: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(.settingsDeprecated)
                    .font(.subheadline.weight(.semibold))
                Text(.settingsDeprecatedFeatureNotice)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 11)
        .background(.orange.opacity(0.1), in: shape)
        .overlay(shape.strokeBorder(.orange.opacity(0.3), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Deprecated badge") {
    DeprecatedFeatureBadge()
        .padding(24)
}

#Preview("Deprecated notice") {
    DeprecatedFeatureNotice()
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Deprecated notice — German, dark") {
    DeprecatedFeatureNotice()
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}
#endif
