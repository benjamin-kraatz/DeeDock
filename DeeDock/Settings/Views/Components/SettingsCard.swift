import SwiftUI

/// A titled group of settings rows drawn as one raised, rounded surface.
///
/// Rows are laid out in order with hairline separators inserted between them, so a pane
/// composes controls without repeating chrome. Rows own their own padding.
struct SettingsCard<Content: View>: View {
    /// Group heading shown above the surface; omit for an unlabeled group.
    var title: LocalizedStringResource?
    /// Explanatory copy shown under the surface in caption style.
    var footnote: LocalizedStringResource?
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            Group(subviews: content) { rows in
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            Divider().padding(.leading, 14)
                        }
                        row
                    }
                }
            }
            // A plain background plus a light overlay separates the surface from the window
            // in both appearances, where a single system fill reads as inset in dark mode.
            .background(.background, in: shape)
            .background(shape.fill(.white.opacity(isDark ? 0.055 : 0)))
            .overlay(shape.strokeBorder(.separator.opacity(isDark ? 0.7 : 0.9), lineWidth: 0.5))
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}
