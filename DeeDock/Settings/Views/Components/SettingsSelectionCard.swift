import SwiftUI

/// The shared finish for a choice in a settings gallery.
///
/// Indicator styles, app-name presets, and reveal animations are all picked from grids of
/// artwork, so they share one selected/unselected treatment instead of three near-misses.
/// The ring uses the pane tint, which keeps a gallery inside the identity color of its pane.
private struct SettingsSelectionCard: ViewModifier {
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    func body(content: Content) -> some View {
        content
            .background(isSelected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.35)),
                        in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator.opacity(0.6)),
                                   lineWidth: isSelected ? 1.5 : 0.5)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.tint)
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(.rect)
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isSelected)
    }
}

extension View {
    /// Marks this view as one option in a settings gallery.
    func settingsSelectionCard(isSelected: Bool) -> some View {
        modifier(SettingsSelectionCard(isSelected: isSelected))
    }
}
