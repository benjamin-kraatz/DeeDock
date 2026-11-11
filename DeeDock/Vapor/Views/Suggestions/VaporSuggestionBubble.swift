import SwiftUI

/// One floating folder bubble: a small glass sphere lit by the same lamp as the orb.
///
/// It springs out of the orb's centre (staggered by `index`), bobs, swells on hover, glides to
/// its new place when the arc changes, and, once eaten, dives back into the orb. The
/// suggestions window covers the orb and sits behind the orb's window, so the bubble is seen
/// passing behind the glass on its way in and out.
struct VaporSuggestionBubble: View {
    let suggestion: VaporSuggestion
    let index: Int
    /// The bubble's resting centre and the orb's centre, in the suggestions window's coordinates.
    let target: CGPoint
    let orb: CGPoint
    let lighting: VaporLighting
    let palette: VaporOrbPalette
    let isEaten: Bool
    let animatesEntrance: Bool
    let reduceMotion: Bool
    let hover: (Bool) -> Void
    let add: () -> Void

    @State private var emerged = false
    @State private var bobbing = false
    @State private var hovered = false

    private static let bobCycles = 3
    private static let bobHalfPeriod: Double = 1.6

    var body: some View {
        let moves = !reduceMotion
        Button(action: add) {
            VaporBubbleGlass(lighting: lighting, palette: palette)
                .scaleEffect(hovered && moves ? 1.16 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: hovered)
                .offset(y: bobbing && moves ? -3 : 0)
                .animation(moves ? .easeInOut(duration: Self.bobHalfPeriod) : nil, value: bobbing)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
        .onHover { isHovered in
            hovered = isHovered && !isEaten
            hover(isHovered && !isEaten)
        }
        .disabled(isEaten)
        .modifier(VaporBubbleFlight(emerge: emerged || !animatesEntrance ? 1 : 0, eat: isEaten ? 1 : 0, rest: target,
                                    orb: orb, landing: CGPoint(x: orb.x, y: orb.y - VaporGeometry.orbDiameter * 0.2),
                                    moves: moves))
        // The arc re-spaces when a neighbour comes or goes: glide there instead of jumping.
        .animation(moves ? VaporMotion.bubbleGlide : nil, value: target)
        .onAppear {
            guard animatesEntrance else { return }
            let delay = reduceMotion ? 0 : Double(index) * VaporMotion.bubbleStagger
            withAnimation((reduceMotion ? Animation.easeOut(duration: 0.2) : VaporMotion.bubbleEnter).delay(delay)) {
                emerged = true
            }
        }
        .task {
            // Each bubble starts its bob a little later, so they drift out of step. The bob is a
            // greeting, not a loop: a few cycles, then the bubble rests, so suggestions that stay
            // up beside Finder cost nothing per frame.
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(animatesEntrance ? 0.6 + Double(index) * 0.7 : 0))
            for _ in 0..<Self.bobCycles {
                guard !Task.isCancelled else { return }
                bobbing = true
                try? await Task.sleep(for: .seconds(Self.bobHalfPeriod))
                guard !Task.isCancelled else { return }
                bobbing = false
                try? await Task.sleep(for: .seconds(Self.bobHalfPeriod))
            }
        }
        .accessibilityLabel(Text(.vaporAddSuggestion(suggestion.name)))
    }
}

/// Where a bubble is between the orb and its place on the arc.
///
/// `emerge` runs 0…1 as the bubble springs out of the orb's centre (it overshoots with the
/// spring), and `eat` runs 0…1 as it dives back in toward `landing`, the spot near the top of
/// the glass where its folder then drops into the pile. The bubble stays solid for most of the
/// dive and only fades over the last stretch, once it is behind the glass, so it reads as going
/// into the orb rather than fading beside it. `rest` is animatable too, for the glide.
///
/// Under Reduce Motion (`moves` false) the bubble stays at `rest` and only fades.
private struct VaporBubbleFlight: ViewModifier, Animatable {
    var emerge: CGFloat
    var eat: CGFloat
    var rest: CGPoint
    let orb: CGPoint
    let landing: CGPoint
    let moves: Bool

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGPoint.AnimatableData> {
        get { AnimatablePair(AnimatablePair(emerge, eat), rest.animatableData) }
        set {
            emerge = newValue.first.first
            eat = newValue.first.second
            rest.animatableData = newValue.second
        }
    }

    func body(content: Content) -> some View {
        let fade = min(max(emerge * 3, 0), 1) * min(max((1 - eat) / 0.4, 0), 1)
        if moves {
            let out = CGPoint(x: orb.x + (rest.x - orb.x) * emerge, y: orb.y + (rest.y - orb.y) * emerge)
            content
                .scaleEffect(max(0.2 + 0.8 * emerge, 0.01) * (1 - 0.68 * eat))
                .opacity(fade)
                .position(x: out.x + (landing.x - out.x) * eat, y: out.y + (landing.y - out.y) * eat)
        } else {
            content
                .opacity(min(max(emerge, 0), 1) * min(max(1 - eat, 0), 1))
                .position(rest)
        }
    }
}

/// The bubble's glass: the orb's tint, a rim, a cool glow at the bottom, a shine turned toward
/// the lamp, and a folder.
private struct VaporBubbleGlass: View {
    let lighting: VaporLighting
    let palette: VaporOrbPalette

    var body: some View {
        let side = VaporGeometry.bubbleDiameter
        ZStack {
            if !palette.reduceTransparency {
                Circle().fill(.clear).glassEffect(.clear, in: Circle())
            }
            Circle().fill(palette.baseGradient)
            VaporInsetGlow(color: VaporOrbPalette.iceBlue.opacity(0.5), offset: -6, blur: 10, spread: -4)
            Circle().strokeBorder(palette.rimLine, lineWidth: 1)
            VaporFolderGlyphView(width: 20)
                .offset(y: 1)
            Ellipse()
                .fill(LinearGradient(colors: [palette.glint, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.85)))
                .frame(width: side * 0.64, height: side * 0.38)
                .opacity(0.75)
                .offset(y: -side * 0.25)
                .rotationEffect(.radians(lighting.angle))
        }
        .frame(width: side, height: side)
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 6, y: 4)
    }
}
