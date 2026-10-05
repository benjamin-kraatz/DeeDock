import SwiftUI

/// Motion shared by every part of the survey card, so a step reads as one surface changing
/// shape rather than separate views swapping. Reduce Motion keeps cross-fades only.
struct LauncherSurveyMotion {
    let reduceMotion: Bool

    /// Card height, progress, and selection changes.
    var morph: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.2) }
    /// Hover and press feedback on chips and rating keys.
    var feedback: Animation { reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.28, bounce: 0.45) }

    /// The next question arrives from the trailing edge as the answered one leaves to the leading edge.
    var step: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .offset(x: 36).combined(with: AnyTransition(.blurReplace)),
                                              removal: .offset(x: -36).combined(with: AnyTransition(.blurReplace)))
    }

    /// The whole card entering or leaving the Suggestions section.
    var card: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .top).combined(with: AnyTransition(.blurReplace))
    }
}

/// A capsule answer option. Hover lifts it; selection fills it with the accent color.
struct LauncherSurveyChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        LauncherSurveyChip(configuration: configuration, isSelected: isSelected)
    }
}

private struct LauncherSurveyChip: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                Capsule().fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary))
                Capsule().strokeBorder(.white.opacity(hovering && !isSelected ? 0.22 : 0.07))
            }
            .shadow(color: .accentColor.opacity(isSelected ? 0.35 : 0), radius: 8, y: 3)
            .contentShape(Capsule())
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.95 : hovering ? 1.04 : 1)
            .opacity(isEnabled || isSelected ? 1 : 0.55)
            .animation(LauncherSurveyMotion(reduceMotion: reduceMotion).feedback, value: hovering)
            .animation(LauncherSurveyMotion(reduceMotion: reduceMotion).feedback, value: configuration.isPressed)
            .onHover { hovering = $0 && isEnabled }
    }
}

/// A small round icon button, such as the card's close button.
struct LauncherSurveyIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LauncherSurveyIconButton(configuration: configuration)
    }
}

private struct LauncherSurveyIconButton: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(hovering ? .primary : .secondary)
            .frame(width: 22, height: 22)
            .background(Circle().fill(.fill.tertiary).opacity(hovering || configuration.isPressed ? 1 : 0))
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Wraps answer chips onto further lines when the launcher is narrow or the options are long.
struct LauncherSurveyWrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indexes {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indexes: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indexes.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indexes.isEmpty {
                rows.append(Row())
            }
            let last = rows.count - 1
            rows[last].width += (rows[last].indexes.isEmpty ? 0 : spacing) + size.width
            rows[last].height = max(rows[last].height, size.height)
            rows[last].indexes.append(index)
        }
        return rows
    }
}
