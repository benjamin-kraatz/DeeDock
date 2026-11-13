import SwiftUI

/// The dock's update tile: one click opens the Update window or the changelog.
struct DockUpdateButton: View {
    let item: UpdateDockItem
    let size: CGFloat
    let selected: Bool
    let interaction: DockInteraction
    let accessibilityFocus: (Bool) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focused: Bool
    @State private var arrived = false

    /// A dock nobody can see, or one that has already faded out, schedules no frames. The tile can
    /// sit in every dock for days, so it follows the same gate as Stardust and the Hub halo.
    private var live: Bool {
        !reduceMotion && interaction.exposesContent && interaction.idleFade.fraction == 0
    }

    var body: some View {
        Button { interaction.openUpdate?(item) } label: {
            DockIconPresentation(
                size: size, edge: interaction.layout.edge, available: true, running: .notRunning,
                launching: false, keyboardSelected: selected,
                artworkOpacity: DockAppearanceOpacity(settings: interaction.idleFade.settings,
                    idleFraction: interaction.idleFade.fraction, reduceTransparency: reduceTransparency).icons,
                artworkAnimation: interaction.idleFade.animation
            ) {
                UpdateTileArtwork(state: item.state, side: size * 0.85, animated: !reduceMotion, playing: live)
                    // The tile grows out of the dock when an update turns up.
                    .scaleEffect(arrived || reduceMotion ? 1 : 0.2)
                    .opacity(arrived || reduceMotion ? 1 : 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) { arrived = true }
        }
        .accessibilityLabel(Text(item.title))
        .accessibilityValue(Text(verbatim: item.version))
        .accessibilityHint(Text(.updatesTileHint))
        .accessibilityFocused($focused)
        .onChange(of: focused) { _, value in accessibilityFocus(value) }
        .onDisappear { accessibilityFocus(false) }
    }
}

/// Artwork of the update tile: a slowly turning indigo-to-coral field, a sheen that crosses
/// it, a breathing halo, and a glyph that moves in a way that fits its state.
///
/// Everything is a continuous function of wrapped time, so nothing jumps at the loop point,
/// and nothing is blurred per frame. Without animation it draws the same tile at rest.
struct UpdateTileArtwork: View {
    let state: UpdateDockItem.State
    let side: CGFloat
    /// False draws the static tile (Reduce Motion).
    let animated: Bool
    /// Whether frames are scheduled right now. The owner folds in dock visibility and idle fade.
    /// Pausing holds the frame drawn last, so an animated tile never jumps to its rest pose.
    var playing = true

    /// Elapsed time wraps to this period. Every rate below is a whole number of cycles in it.
    private static let period: Double = 24

    /// The turn shown when playback last stopped; playback resumes from it.
    @State private var heldTurn: Double = 0
    /// When the current playback started.
    @State private var startedAt = Date()

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { context in
                tile(turn: playing ? turn(at: context.date) : heldTurn)
            }
            .onChange(of: playing) { _, plays in
                if plays {
                    startedAt = .now
                } else {
                    heldTurn = turn(at: .now)
                }
            }
        } else {
            tile(turn: 0.1)
        }
    }

    /// Wrapped turn in 0..<1. Every rate is whole cycles per period, so the wrap is seamless.
    private func turn(at date: Date) -> Double {
        let turns = heldTurn + date.timeIntervalSince(startedAt) / Self.period
        return turns - turns.rounded(.down)
    }

    private func tile(turn: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.26, style: .continuous)
        // 2 field turns, 6 breaths and 4 sheen passes per period.
        let field = turn * 2 * 2 * .pi
        let breath = (sin(turn * 6 * 2 * .pi) + 1) / 2
        let sheen = (turn * 4).truncatingRemainder(dividingBy: 1)
        let start = UnitPoint(x: 0.5 + 0.5 * cos(field), y: 0.5 + 0.5 * sin(field))
        let end = UnitPoint(x: 0.5 - 0.5 * cos(field), y: 0.5 - 0.5 * sin(field))
        return ZStack {
            shape
                .fill(LinearGradient(colors: [UpdateAwarenessTint.indigo, UpdateAwarenessTint.violet,
                                              UpdateAwarenessTint.coral],
                                     startPoint: start, endPoint: end))
            // Depth: light from above, shade below.
            shape.fill(LinearGradient(colors: [.white.opacity(0.28), .clear, .black.opacity(0.16)],
                                      startPoint: .top, endPoint: .bottom))
            // A narrow band of light that enters at one corner and leaves at the other, then rests.
            shape
                .fill(LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.5), location: 0.5),
                    .init(color: .clear, location: 1)
                ], startPoint: .leading, endPoint: .trailing))
                .frame(width: side * 0.5)
                .rotationEffect(.degrees(24))
                .offset(x: (min(sheen * 2.6, 1) * 2 - 1) * side * 1.1)
                .opacity(animated ? 1 : 0)
                .frame(width: side, height: side)
                .clipShape(shape)
            glyph(turn: turn)
            shape.strokeBorder(.white.opacity(0.35), lineWidth: max(1, side * 0.02))
        }
        .frame(width: side, height: side)
        .shadow(color: UpdateAwarenessTint.coral.opacity(0.25 + 0.4 * breath), radius: side * (0.06 + 0.08 * breath))
        .scaleEffect(1 + 0.025 * breath)
    }

    @ViewBuilder private func glyph(turn: Double) -> some View {
        let image = Image(systemName: UpdateDockItem(state: state, version: "").symbol)
            .font(.system(size: side * 0.46, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: side * 0.03, y: side * 0.02)
        switch state {
        case .available:
            // The arrow dips, as if dropping something into the dock. 12 dips per period.
            image.offset(y: sin(turn * 12 * 2 * .pi) * side * 0.06)
        case .ready:
            // One calm turn every four seconds.
            image.rotationEffect(.radians(turn * 6 * 2 * .pi))
        case .installed:
            // The sparkles twinkle: a slow swell with a slight rock.
            image.scaleEffect(1 + 0.12 * sin(turn * 12 * 2 * .pi))
                .rotationEffect(.degrees(8 * sin(turn * 6 * 2 * .pi)))
        }
    }
}

/// Tile colours. Kept apart from the direct-only badge mark so every target can draw the tile.
enum UpdateAwarenessTint {
    static let indigo = Color(red: 0.36, green: 0.34, blue: 0.92)
    static let violet = Color(red: 0.72, green: 0.38, blue: 0.86)
    static let coral = Color(red: 0.98, green: 0.47, blue: 0.40)
}

#Preview("Update tiles") {
    HStack(spacing: 24) {
        UpdateTileArtwork(state: .available, side: 64, animated: true)
        UpdateTileArtwork(state: .ready, side: 64, animated: true)
        UpdateTileArtwork(state: .installed, side: 64, animated: true)
        UpdateTileArtwork(state: .ready, side: 64, animated: false)
        UpdateTileArtwork(state: .ready, side: 64, animated: true, playing: false)
    }
    .padding(40)
    .background(.black.opacity(0.7))
}
