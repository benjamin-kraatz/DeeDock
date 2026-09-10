import SwiftUI

/// The greenhouse bed: every pinned Action Tile laid out as a plant on soil behind glass.
///
/// This view only presents plants. Watering calls back through `water`, which the owner wires to
/// ``ActionTilesController/water(_:)`` so the existing Action Tiles runner stays the only runner.
/// The view is never shown when the greenhouse preference is off; the Settings card decides that.
struct ShortcutGreenhouseView: View {
    let plants: [ShortcutGreenhousePlant]
    /// Runs the shortcut for one plant, keyed by ``ShortcutGreenhousePlant/id``.
    let water: (UUID) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background(backdrop)
            .overlay { if !reduceTransparency { ShortcutGreenhouseGlass() } }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(.greenhouseTitle))
    }

    @ViewBuilder private var content: some View {
        if plants.isEmpty {
            ContentUnavailableView {
                Label { Text(.greenhouseTitle) } icon: { Image(systemName: "leaf") }
            } description: {
                Text(.greenhouseEmpty)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else {
            bed
        }
    }

    private var bed: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .bottom)],
                  alignment: .leading, spacing: 16) {
            ForEach(plants, id: \.id) { plant in
                ShortcutGreenhousePlantView(plant: plant, water: { water(plant.id) })
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(alignment: .bottom) { soil }
    }

    /// A soil band under the plants, thin enough that the pots still read as standing on it.
    private var soil: some View {
        LinearGradient(colors: [Color.brown.opacity(0.05), Color.brown.opacity(0.35)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 22)
    }

    @ViewBuilder private var backdrop: some View {
        if reduceTransparency {
            Color(nsColor: .controlBackgroundColor)
        } else {
            Rectangle().fill(.thinMaterial)
        }
    }
}

/// Glass panes hinted with hairline mullions, drawn over the material rather than as a bitmap theme.
///
/// Purely decorative, so it is hidden from accessibility and dropped entirely under
/// Reduce Transparency, where an opaque surface replaces the material.
private struct ShortcutGreenhouseGlass: View {
    var body: some View {
        GeometryReader { proxy in
            let panes = max(2, Int(proxy.size.width / 120))
            let step = proxy.size.width / CGFloat(panes)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.white.opacity(0.06))
                    .frame(height: 10)
                ForEach(1..<panes, id: \.self) { index in
                    Rectangle()
                        .fill(.separator.opacity(0.25))
                        .frame(width: 0.5)
                        .offset(x: step * CGFloat(index))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Bed with healthy and wilted") {
    ShortcutGreenhouseView(plants: ShortcutGreenhousePlant.previewBed, water: { _ in })
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Empty bed") {
    ShortcutGreenhouseView(plants: [], water: { _ in })
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Reduce Transparency") {
    ShortcutGreenhouseView(plants: ShortcutGreenhousePlant.previewBed, water: { _ in })
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
        .environment(\.accessibilityReduceTransparency, true)
}

#Preview("Dark") {
    ShortcutGreenhouseView(plants: ShortcutGreenhousePlant.previewBed, water: { _ in })
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
        .preferredColorScheme(.dark)
}
#endif
