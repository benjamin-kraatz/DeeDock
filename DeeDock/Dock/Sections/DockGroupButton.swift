import SwiftUI

/// A section action, deliberately separate from application launch, pin, and drag-source plumbing.
struct DockGroupButton: View {
    let control: DockGroupControl
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let reduceTransparency: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool

    var body: some View {
        let edge = interaction.layout.edge
        let bounds = edge.size(length: size, depth: size + DockGeometry.indicatorAreaDepth)
        let center = edge.point(CGPoint(x: size / 2, y: size / 2), depth: size + DockGeometry.indicatorAreaDepth)
        let opacity = DockAppearanceOpacity(settings: interaction.idleFade.settings,
            idleFraction: interaction.idleFade.fraction, reduceTransparency: reduceTransparency)
        Button { interaction.toggleSection?() } label: {
            ZStack(alignment: .topLeading) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.08))
                    VStack(spacing: 2) {
                        Image(systemName: control.symbol).font(.system(size: size * 0.32))
                        HStack(spacing: 3) {
                            Text(control.count, format: .number).monospacedDigit()
                            Image(systemName: control.expanded ? "chevron.down" : "chevron.right")
                        }.font(.system(size: max(9, size * 0.2), weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                }
                .frame(width: size, height: size)
                .animation(interaction.idleFade.animation) { $0.opacity(opacity.icons) }
                .overlay {
                    if selected { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 2) }
                }
                .position(center)
            }
            .frame(width: bounds.width, height: bounds.height)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(control.title))
        .accessibilityValue(Text(control.expanded ? .sectionExpanded : .sectionCollapsed))
        .accessibilityFocused($accessibilityFocused)
        .onChange(of: accessibilityFocused) { _, focused in
            interaction.accessibilityFocusChanged?(DockEntryID.group(control.group).hitID, focused)
        }
        .onDisappear { interaction.accessibilityFocusChanged?(DockEntryID.group(control.group).hitID, false) }
    }
}
