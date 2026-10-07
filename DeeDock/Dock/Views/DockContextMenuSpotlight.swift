import SwiftUI

/// Marks the tile whose context menu is open so it stays identifiable while the menu tracks.
///
/// The owner hops out of the dock to the side of the menu and grows slightly; every other tile
/// recedes. Apply this before a tile's geometry reporting: offset and scale are render-only, so
/// published hit and tooltip frames stay at rest.
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

    let role: Role
    /// Where the owner sits while its menu is open, from ``DockContextMenuPlacement``.
    let offset: CGSize
    let reduceMotion: Bool
    /// Receding by opacity would turn opaque icons translucent, so Reduce Transparency darkens instead.
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        let owner = role == .owner
        let receded = role == .receded
        content
            // Reduce Motion still moves the owner, because the menu would otherwise cover it, but
            // without travel: it appears beside the menu.
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.72)) {
                $0.scaleEffect(owner && !reduceMotion ? Self.scale : 1)
                    .offset(owner ? offset : .zero)
            }
            .animation(.easeOut(duration: 0.15)) {
                $0.saturation(receded ? 0.45 : 1)
                    .brightness(receded && reduceTransparency ? -0.25 : 0)
                    .opacity(receded && !reduceTransparency ? 0.45 : 1)
            }
    }
}

#if DEBUG
    #Preview("Owner hopped, others receded") {
        HStack(spacing: 12) {
            ForEach(Array(DockPreviewData.items.prefix(4).enumerated()), id: \.element.id) { index, item in
                Image(nsImage: item.icon).resizable().frame(width: 48, height: 48)
                    .modifier(DockContextMenuSpotlight(role: index == 2 ? .owner : .receded,
                                                       offset: CGSize(width: -20, height: -56),
                                                       reduceMotion: false, reduceTransparency: false))
            }
        }
        .padding(.top, 72)
        .padding(20)
    }

    #Preview("Reduce Transparency") {
        HStack(spacing: 12) {
            ForEach(Array(DockPreviewData.items.prefix(4).enumerated()), id: \.element.id) { index, item in
                Image(nsImage: item.icon).resizable().frame(width: 48, height: 48)
                    .modifier(DockContextMenuSpotlight(role: index == 2 ? .owner : .receded,
                                                       offset: CGSize(width: -20, height: -56),
                                                       reduceMotion: true, reduceTransparency: true))
            }
        }
        .padding(.top, 72)
        .padding(20)
    }
#endif
