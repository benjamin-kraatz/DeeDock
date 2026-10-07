import SwiftUI

/// Marks the tile whose context menu is open so it stays identifiable while the menu tracks.
///
/// The owner lifts toward the screen and grows slightly; every other tile recedes. Apply this
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

    /// How far the owner rises toward the screen, in points. Menu placement clears it.
    static let lift: CGFloat = 5
    /// The owner's growth, anchored at the dock edge. Menu placement clears it.
    static let scale: CGFloat = 1.06

    let role: Role
    let edge: DockEdge
    let reduceMotion: Bool
    /// Receding by opacity would turn opaque icons translucent, so Reduce Transparency darkens instead.
    let reduceTransparency: Bool

    private var lifted: Bool { role == .owner && !reduceMotion }

    /// Grow away from the screen edge so the tile keeps its baseline against the glass.
    private var anchor: UnitPoint {
        switch edge {
        case .bottom: .bottom
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }

    func body(content: Content) -> some View {
        let lift = edge.offset(CGSize(width: 0, height: lifted ? -Self.lift : 0))
        let receded = role == .receded
        content
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.7)) {
                $0.scaleEffect(lifted ? Self.scale : 1, anchor: anchor)
                    .offset(lift)
                    .saturation(receded ? 0.45 : 1)
                    .brightness(receded && reduceTransparency ? -0.25 : 0)
                    .opacity(receded && !reduceTransparency ? 0.45 : 1)
            }
    }
}

#if DEBUG
    #Preview("Owner and receded tiles") {
        HStack(spacing: 12) {
            ForEach(Array(DockPreviewData.items.prefix(4).enumerated()), id: \.element.id) { index, item in
                Image(nsImage: item.icon).resizable().frame(width: 48, height: 48)
                    .modifier(DockContextMenuSpotlight(role: index == 1 ? .owner : .receded, edge: .bottom,
                                                       reduceMotion: false, reduceTransparency: false))
            }
        }
        .padding(20)
    }

    #Preview("Reduce Transparency") {
        HStack(spacing: 12) {
            ForEach(Array(DockPreviewData.items.prefix(4).enumerated()), id: \.element.id) { index, item in
                Image(nsImage: item.icon).resizable().frame(width: 48, height: 48)
                    .modifier(DockContextMenuSpotlight(role: index == 1 ? .owner : .receded, edge: .bottom,
                                                       reduceMotion: true, reduceTransparency: true))
            }
        }
        .padding(20)
    }
#endif
