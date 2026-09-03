import SwiftUI

/// A desktop you point at to place the dock.
///
/// The four edges of the screen are the control. There is no picker to read and map back onto a
/// diagram, because the diagram is the picker: click an edge, and the dock — drawn with the same
/// `DockPlacement` calculation a real dock uses — moves there, on screen and on the desktop.
///
/// The handles sit outside the bezel rather than inside it. Anything laid over the desktop would
/// cover the dock it is meant to place, and an edge of the screen is exactly where a person
/// expects the control for that edge to be. Each handle is drawn as a small dock so its meaning
/// survives without a label.
struct OnboardingPlacementPicker: View {
    /// The edge currently chosen, written straight through to shared defaults.
    let edge: DockEdge
    var select: (DockEdge) -> Void = { _ in }
    /// Identity color for the chosen handle; defaults to the placement page's own tint.
    var tint: Color = OnboardingStep.placement.tint
    /// Previews pass an explicit value; the picker otherwise follows the system setting.
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    @State private var hovered: DockEdge?

    /// A stand-in desktop, matching the proportions `DockDisplayDiagram` uses so the tour and
    /// the Settings previews describe the same screen.
    private static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private static let menuBar: CGFloat = 64
    private static let scale: CGFloat = 0.23
    /// Clearance between the screen and its handles, wide enough that a handle never reads
    /// as part of the desktop.
    private static let gap: CGFloat = 11
    private static let handleLength: CGFloat = 40
    private static let handleThickness: CGFloat = 14

    private var size: CGSize {
        CGSize(width: Self.screen.width * Self.scale, height: Self.screen.height * Self.scale)
    }

    var body: some View {
        VStack(spacing: Self.gap) {
            handle(.top)
            HStack(spacing: Self.gap) {
                handle(.left)
                ZStack {
                    desktop
                    dock
                }
                .frame(width: size.width, height: size.height)
                handle(.right)
            }
            handle(.bottom)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: edge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.onboardingPlacementPickerLabel))
    }

    private var desktop: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.indigo.gradient)
            .overlay(alignment: .top) {
                Rectangle().fill(.black.opacity(0.18)).frame(height: Self.menuBar * Self.scale)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
            }
    }

    /// The dock itself, positioned by the production placement calculation rather than by four
    /// hand-written cases, so an edge that looks right here is right on the desktop.
    private var dock: some View {
        let glass = glassRect
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: min(glass.width, glass.height) * 0.28, style: .continuous)
                .fill(.white.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: min(glass.width, glass.height) * 0.28, style: .continuous)
                        .strokeBorder(.white.opacity(0.45), lineWidth: 0.5)
                }
                .frame(width: glass.width, height: glass.height)
                .position(x: glass.midX, y: glass.midY)
            ForEach(iconRects.indices, id: \.self) { index in
                let rect = iconRects[index]
                RoundedRectangle(cornerRadius: rect.width * 0.24, style: .continuous)
                    .fill(Self.iconColors[index % Self.iconColors.count])
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private static let iconColors: [Color] = [.blue, .cyan, .pink, .orange, .gray, .mint]

    /// A miniature dock on each side of the screen: quiet at rest, tinted on hover, filled on
    /// the edge in use. Its shape says what choosing it does, so no caption is needed.
    private func handle(_ candidate: DockEdge) -> some View {
        let isSelected = candidate == edge
        let isHovered = hovered == candidate
        let length = Self.handleLength
        let thickness = Self.handleThickness
        return Button { select(candidate) } label: {
            RoundedRectangle(cornerRadius: thickness * 0.36, style: .continuous)
                .fill(surface(isSelected: isSelected, isHovered: isHovered))
                .frame(width: candidate.isVertical ? thickness : length,
                       height: candidate.isVertical ? length : thickness)
                .overlay { icons(candidate, isSelected: isSelected, isHovered: isHovered) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovered = $0 ? candidate : (hovered == candidate ? nil : hovered) }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isHovered)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isSelected)
        .help(Text(candidate.placementLabel))
        .accessibilityLabel(Text(candidate.placementLabel))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func surface(isSelected: Bool, isHovered: Bool) -> AnyShapeStyle {
        if isSelected { return AnyShapeStyle(tint) }
        if isHovered { return AnyShapeStyle(tint.opacity(0.28)) }
        return AnyShapeStyle(.quaternary)
    }

    /// Three marks standing in for dock icons, laid along the handle the way they would sit on
    /// that edge — stacked beside the screen, in a row above or below it.
    private func icons(_ candidate: DockEdge, isSelected: Bool, isHovered: Bool) -> some View {
        let color: Color = isSelected ? .white : isHovered ? tint : .secondary
        let marks = ForEach(0..<3, id: \.self) { _ in
            Circle().fill(color.opacity(isSelected ? 0.95 : 0.65)).frame(width: 4, height: 4)
        }
        return Group {
            if candidate.isVertical {
                VStack(spacing: 4) { marks }
            } else {
                HStack(spacing: 4) { marks }
            }
        }
    }

    // MARK: - Production geometry

    private var settings: DockSettings {
        DockSettings(iconSize: 44, magnification: 1, itemSpacing: 4, edge: edge,
                     alignment: .center, edgeDistance: 10)
    }

    private var visibleFrame: CGRect {
        CGRect(x: Self.screen.minX, y: Self.screen.minY,
               width: Self.screen.width, height: Self.screen.height - Self.menuBar)
    }

    private var layout: DockGeometry.Layout {
        let reference = DockGeometry.referenceFrame(screenFrame: Self.screen, visibleFrame: visibleFrame,
                                                    settings: settings)
        return DockGeometry.layout(count: 6, favoriteCount: 3,
                                   availableLength: settings.edge.length(of: reference.size),
                                   availableDepth: settings.edge.depth(of: reference.size), settings: settings)
    }

    private var panelFrame: CGRect {
        let reference = DockGeometry.referenceFrame(screenFrame: Self.screen, visibleFrame: visibleFrame,
                                                    settings: settings)
        return DockGeometry.panelFrame(referenceFrame: reference, layout: layout, settings: settings)
    }

    /// Converts an AppKit screen rectangle into the view's top-left space at diagram scale.
    private func scaled(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * Self.scale, y: (Self.screen.maxY - rect.maxY) * Self.scale,
               width: rect.width * Self.scale, height: rect.height * Self.scale)
    }

    private var glassRect: CGRect {
        scaled(DockGeometry.restingGlass(frame: panelFrame, layout: layout))
    }

    private var iconRects: [CGRect] {
        let layout = layout
        let frame = panelFrame
        return layout.restingCenters.map { center in
            scaled(DockEdge.screenRect(layout.iconFrame(centerAlong: center, size: layout.iconSize), in: frame))
        }
    }
}

private extension DockEdge {
    /// Accessible name for a placement target. The visual control is a strip on the diagram,
    /// which needs a spoken name of its own.
    var placementLabel: LocalizedStringResource {
        switch self {
        case .bottom: .onboardingPlacementBottom
        case .top: .onboardingPlacementTop
        case .left: .onboardingPlacementLeft
        case .right: .onboardingPlacementRight
        }
    }
}

#if DEBUG
private struct PlacementPickerHarness: View {
    @State private var edge: DockEdge = .bottom
    var body: some View {
        OnboardingStage(tint: OnboardingStep.placement.tint) {
            OnboardingPlacementPicker(edge: edge, select: { edge = $0 })
        }
        .padding(28).frame(width: 700)
    }
}

#Preview("Placement picker") { PlacementPickerHarness() }

#Preview("Placement picker — every edge") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        ForEach(DockEdge.allCases, id: \.self) { edge in
            OnboardingPlacementPicker(edge: edge).scaleEffect(0.62).frame(width: 260, height: 185)
        }
    }.padding()
}
#endif
