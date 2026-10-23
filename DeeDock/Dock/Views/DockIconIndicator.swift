import SwiftUI

/// Running-state artwork inside the icon square. It never changes layout or hit regions.
/// Apply before keyboard focus and launch overlays so those interaction states stay on top.
///
/// These styles are decoration laid over any icon. `variant` and `animated` are used only
/// by Stardust; every other style ignores them.
///
/// An app running in background keeps the same figure in ``DockIndicatorMutedInk`` grays, and
/// Stardust stops twinkling. Both figures stay stacked while the app runs so a change between
/// running and background crossfades in place; under Reduce Motion it switches at once.
struct DockIconIndicator: ViewModifier {
    let style: DockSettings.RunningIndicatorStyle
    let state: DockRunningState
    let size: CGFloat
    var variant: DockIndicatorVariant = .neutral
    var animated: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if state.showsIndicator {
                    Group {
                        if style == .stardust {
                            // One clock drives both sparkle fields, so they crossfade in place.
                            DockStardust(size: size, variant: variant, animated: animated && !reduceMotion, state: state)
                        } else {
                            ZStack {
                                DockIndicatorForeground(style: style, size: size)
                                    .opacity(state == .running ? 1 : 0)
                                DockIndicatorForeground(style: style, size: size, muted: true)
                                    .opacity(state == .background ? 1 : 0)
                            }
                        }
                    }
                    .animation(reduceMotion ? nil : DockRunningIndicator.stateAnimation, value: state)
                    // A launch or quit shows or removes the figure at once, as before.
                    .transition(.identity)
                    .accessibilityHidden(true).allowsHitTesting(false)
                }
            }
    }
}

/// Fixed grays for an overlay figure on an app running in background.
///
/// The figures sit on the icon's artwork, not on the dock's glass, so they do not follow the
/// appearance: a hierarchical gray vanishes on a white icon in dark mode and turns almost black
/// in light mode, and the same app would show two different figures. A light silver over a
/// half-strength dark outline stays readable on dark, white and saturated icons in both
/// appearances, and reads as the running figure gone gray.
enum DockIndicatorMutedInk {
    /// Strokes and fills that replace the style's colour.
    static let fill = Color(white: 0.72).opacity(0.85)
    /// The Orbit ring, a little lighter than its moons so they still lead.
    static let ring = Color(white: 0.72).opacity(0.75)
    /// The dark edge that separates a figure from the artwork, softened to match.
    static let outline = Color.black.opacity(0.45)
    /// The Power Badge bolt on its silver disc.
    static let glyph = Color.black.opacity(0.6)
}

/// Frames and corner ornaments leave the center of each app icon recognizable.
/// Stardust draws itself; see ``DockStardust``.
private struct DockIndicatorForeground: View {
    let style: DockSettings.RunningIndicatorStyle
    let size: CGFloat
    /// Draws the same figure in ``DockIndicatorMutedInk`` for an app running in background.
    var muted = false

    /// The style's own colour, or the muted ink that replaces it.
    private func paint(_ color: Color, _ ink: Color) -> AnyShapeStyle {
        AnyShapeStyle(muted ? ink : color)
    }

    var body: some View {
        ZStack {
            switch style {
            case .targetLock:
                DockTargetBrackets()
                    .stroke(paint(.black, DockIndicatorMutedInk.outline),
                            style: StrokeStyle(lineWidth: max(4, size * 0.08), lineCap: .square))
                    .padding(size * 0.075)
                DockTargetBrackets()
                    .stroke(paint(.green, DockIndicatorMutedInk.fill),
                            style: StrokeStyle(lineWidth: max(2, size * 0.04), lineCap: .square))
                    .padding(size * 0.075)
            case .orbit:
                Circle().trim(from: 0.06, to: 0.88)
                    .stroke(muted ? AnyShapeStyle(DockIndicatorMutedInk.ring)
                                  : AnyShapeStyle(AngularGradient(colors: [.cyan, .indigo, .purple, .cyan], center: .center)),
                            style: StrokeStyle(lineWidth: max(2, size * 0.035), lineCap: .round))
                    .padding(size * 0.045)
                Circle().fill(paint(.cyan, DockIndicatorMutedInk.fill))
                    .overlay { Circle().strokeBorder(paint(.black, DockIndicatorMutedInk.outline), lineWidth: 1) }
                    .frame(width: size * 0.14, height: size * 0.14)
                    .position(x: size * 0.85, y: size * 0.20)
                Circle().fill(paint(.purple, DockIndicatorMutedInk.fill))
                    .frame(width: size * 0.09, height: size * 0.09)
                    .position(x: size * 0.16, y: size * 0.80)
            case .powerBadge:
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.19, weight: .black))
                    .foregroundStyle(paint(.black, DockIndicatorMutedInk.glyph))
                    .frame(width: size * 0.34, height: size * 0.34)
                    .background(paint(.yellow, DockIndicatorMutedInk.fill), in: Circle())
                    .overlay {
                        Circle().strokeBorder(paint(.black, DockIndicatorMutedInk.outline),
                                              lineWidth: max(1, size * 0.025))
                    }
                    .position(x: size * 0.79, y: size * 0.20)
            default:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
    }
}

/// Four disconnected corners, with no crosshair over the application's artwork.
private struct DockTargetBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arm = rect.width * 0.22
        for x in [rect.minX, rect.maxX] {
            for y in [rect.minY, rect.maxY] {
                let dx: CGFloat = x == rect.minX ? arm : -arm
                let dy: CGFloat = y == rect.minY ? arm : -arm
                path.move(to: CGPoint(x: x + dx, y: y))
                path.addLine(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y + dy))
            }
        }
        return path
    }
}

#if DEBUG
/// Every overlay style on dark, white and saturated stand-in icons. Toggle the state to watch the
/// crossfade; Stardust keeps twinkling while running and holds its constellation when muted.
private struct DockIconIndicatorGallery: View {
    let scheme: ColorScheme
    @State private var background = false
    private let styles: [DockSettings.RunningIndicatorStyle] = [.targetLock, .orbit, .stardust, .powerBadge]
    private let icons: [(name: String, style: AnyShapeStyle)] = [
        ("dark", AnyShapeStyle(Color(white: 0.15).gradient)),
        ("white", AnyShapeStyle(Color.white.gradient)),
        ("indigo", AnyShapeStyle(Color.indigo.gradient)),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                ForEach(icons, id: \.name) { icon in
                    GridRow {
                        ForEach(styles, id: \.self) { style in
                            RoundedRectangle(cornerRadius: 12).fill(icon.style)
                                .padding(5)
                                .frame(width: 64, height: 64)
                                .modifier(DockIconIndicator(style: style, state: background ? .background : .running,
                                                            size: 64, variant: DockIndicatorVariant(identity: style.rawValue),
                                                            animated: true))
                        }
                    }
                }
            }
            Toggle(isOn: $background) { Text(.appStatusRunningInBackground) }
        }
        .padding(20)
        .background(.regularMaterial)
        .preferredColorScheme(scheme)
    }
}

#Preview("Overlay styles, running or background, light") { DockIconIndicatorGallery(scheme: .light) }
#Preview("Overlay styles, running or background, dark") { DockIconIndicatorGallery(scheme: .dark) }
#endif
