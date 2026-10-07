import SwiftUI

/// Marks the tile whose context menu is open so it stays identifiable while the menu tracks.
///
/// The owner moves beside the menu and grows slightly; every other tile recedes. Apply this
/// before a tile's geometry reporting: offset and scale are render-only, so published hit and
/// tooltip frames stay at rest.
struct DockContextMenuSpotlight: ViewModifier {
    enum Role: Equatable {
        /// No context menu is open on this dock.
        case none
        /// This tile opened the menu.
        case owner
        /// Another tile opened the menu.
        case receded
    }

    /// The owner's growth while it sits beside the menu.
    static let scale: CGFloat = 1.06
    /// Slide Out's travel. ``DockContextMenuReveal/slideLead`` holds the menu back until most of
    /// it has played.
    static let slide = Animation.spring(response: 0.24, dampingFraction: 0.86)
    /// The way home once the menu has closed, which nothing covers in any style.
    static let home = Animation.spring(response: 0.3, dampingFraction: 0.82)

    let role: Role
    /// Where the owner sits while its menu is open, from ``DockContextMenuPlacement``.
    let offset: CGSize
    let reveal: DockContextMenuReveal
    let reduceMotion: Bool
    /// Receding by opacity would turn opaque icons translucent, so Reduce Transparency darkens instead.
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        let owner = role == .owner
        let receded = role == .receded
        let reveal = reveal.effective(reduceMotion: reduceMotion)
        let moves = owner && reveal != .off
        // Pop Out jumps while the menu window covers the slot it leaves, then plays its arrival
        // beside the menu. Slide Out travels before the menu opens. Once the menu closes, every
        // style travels home in view.
        let travel: Animation? = reduceMotion ? nil : (moves ? (reveal == .slideOut ? Self.slide : nil) : Self.home)
        let popsIn = moves && reveal == .popOut
        content
            // Scales around the tile's own center, inside the offset, so the pop happens where the
            // tile lands rather than growing out of the slot it left.
            .keyframeAnimator(initialValue: 1.0, trigger: owner) { view, arrival in
                view.scaleEffect(reduceMotion ? 1 : 0.4 + 0.6 * arrival)
                    .opacity(min(1, arrival))
            } keyframes: { _ in
                // At rest `arrival` is 1, so a tile that is not popping in draws unchanged.
                KeyframeTrack {
                    MoveKeyframe(popsIn ? 0.0 : 1.0)
                    if reduceMotion {
                        LinearKeyframe(1.0, duration: 0.15)
                    } else {
                        SpringKeyframe(1.0, duration: 0.5, spring: Spring(response: 0.42, dampingRatio: 0.58))
                    }
                }
            }
            .animation(travel) {
                $0.scaleEffect(moves && !reduceMotion ? Self.scale : 1)
                    .offset(moves ? offset : .zero)
            }
            .animation(.easeOut(duration: 0.15)) {
                $0.saturation(receded ? 0.45 : 1)
                    .brightness(receded && reduceTransparency ? -0.25 : 0)
                    .opacity(receded && !reduceTransparency ? 0.45 : 1)
            }
    }
}

#if DEBUG
    private struct SpotlightPreview: View {
        let reveal: DockContextMenuReveal
        var reduceMotion = false
        var reduceTransparency = false
        @State private var owner: Int?

        var body: some View {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    ForEach(Array(DockPreviewData.items.prefix(4).enumerated()), id: \.element.id) { index, item in
                        Image(nsImage: item.icon).resizable().frame(width: 48, height: 48)
                            .modifier(DockContextMenuSpotlight(
                                role: owner == nil ? .none : (owner == index ? .owner : .receded),
                                offset: CGSize(width: -36, height: -60), reveal: reveal,
                                reduceMotion: reduceMotion, reduceTransparency: reduceTransparency))
                            .onTapGesture { owner = owner == index ? nil : index }
                    }
                }
                Text(verbatim: "Click an icon to toggle its menu").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 72)
            .padding(20)
        }
    }

    #Preview("Pop out") { SpotlightPreview(reveal: .popOut) }
    #Preview("Slide out") { SpotlightPreview(reveal: .slideOut) }
    #Preview("Off") { SpotlightPreview(reveal: .off) }
    #Preview("Reduce Motion and Transparency") {
        SpotlightPreview(reveal: .slideOut, reduceMotion: true, reduceTransparency: true)
    }
#endif
