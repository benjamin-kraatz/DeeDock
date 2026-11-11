import SwiftUI

/// One floating folder bubble: a small glass sphere lit by the same lamp as the orb.
///
/// It springs out of the orb's centre (staggered by `index`), bobs, swells on hover and, once
/// eaten, flies back into the orb while shrinking and fading.
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

    @State private var arrived = false
    @State private var bobbing = false
    @State private var hovered = false

    var body: some View {
        let inPlace = arrived || !animatesEntrance
        let atRest = inPlace && !isEaten
        let moves = !reduceMotion
        Button(action: add) {
            VaporBubbleGlass(lighting: lighting, palette: palette)
                .scaleEffect(hovered && moves ? 1.16 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: hovered)
                .offset(y: bobbing && moves ? -3 : 0)
                .animation(moves ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true) : nil, value: bobbing)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
        .onHover { isHovered in
            hovered = isHovered && !isEaten
            hover(isHovered && !isEaten)
        }
        .disabled(isEaten)
        .scaleEffect(moves ? (atRest ? 1 : (isEaten ? 0.25 : 0.2)) : 1)
        .opacity(atRest ? 1 : 0)
        .position(moves && !atRest ? orb : target)
        .onAppear {
            guard animatesEntrance else {
                bobbing = true
                return
            }
            let delay = reduceMotion ? 0 : Double(index) * VaporMotion.bubbleStagger
            withAnimation((reduceMotion ? Animation.easeOut(duration: 0.2) : VaporMotion.bubbleEnter).delay(delay)) {
                arrived = true
            }
            // Each bubble starts its bob a little later, so they drift out of step.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.6 + Double(index) * 0.7))
                bobbing = true
            }
        }
        .accessibilityLabel(Text(.vaporAddSuggestion(suggestion.name)))
    }
}

/// The bubble's glass: the orb's tint, a rim, a cool glow at the bottom, a shine turned toward
/// the lamp, and a folder icon.
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
            Ellipse()
                .fill(LinearGradient(colors: [palette.glint, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.85)))
                .frame(width: side * 0.64, height: side * 0.38)
                .opacity(0.75)
                .offset(y: -side * 0.25)
                .rotationEffect(.radians(lighting.angle))
            VaporFolderIcon(size: 20)
                .offset(y: 1)
        }
        .frame(width: side, height: side)
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 6, y: 4)
    }
}
