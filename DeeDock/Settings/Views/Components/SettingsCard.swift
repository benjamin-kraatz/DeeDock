import SwiftUI

extension EnvironmentValues {
    /// The open page's title key. A card whose heading repeats it drops the heading, since the
    /// window toolbar already names the page.
    @Entry var settingsPageTitleKey: String? = nil
}

/// A titled group of settings rows drawn as one neutral, rounded group.
///
/// Rows are laid out in order with hairline separators inserted between them, so a pane
/// composes controls without repeating chrome. Rows own their own padding, and every row
/// stretches to the full width so labels in one card share a leading edge.
struct SettingsCard<Content: View>: View {
    /// Group heading shown above the surface; omit for an unlabeled group.
    var title: LocalizedStringResource?
    /// Explanatory copy shown under the surface in caption style.
    var footnote: LocalizedStringResource?
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.settingsPageTitleKey) private var pageTitleKey

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
    }
    private var isDark: Bool { colorScheme == .dark }
    private var heading: LocalizedStringResource? {
        guard let title, title.key != pageTitleKey else { return nil }
        return title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let heading {
                Text(heading)
                    .font(.headline)
                    .padding(.leading, SettingsMetrics.captionInset)
                    .accessibilityAddTraits(.isHeader)
            }
            Group(subviews: content) { rows in
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            Divider()
                                .padding(.leading, SettingsMetrics.rowInset)
                                .opacity(isDark ? 0.7 : 1)
                        }
                        row.frame(maxWidth: .infinity)
                    }
                }
            }
            .background(.background.secondary, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.separator.opacity(isDark ? 0.6 : 0.4), lineWidth: 0.5))
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SettingsMetrics.captionInset)
            }
        }
    }
}
