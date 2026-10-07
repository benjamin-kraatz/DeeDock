import SwiftUI

/// Marks the tile whose context menu is open so it stays identifiable while the menu tracks.
///
/// The owner keeps its place and full color while every other tile recedes. The menu opens at the
/// pointer and may cover the owner. Moving the owner out from under it was tried and dropped: the
/// menu window draws above the dock and hid most of the motion.
struct DockContextMenuSpotlight: ViewModifier {
    enum Role: Equatable {
        /// No context menu is open on this dock.
        case none
        /// This tile opened the menu.
        case owner
        /// Another tile opened the menu.
        case receded
    }

    let role: Role
    /// Receding by opacity would turn opaque icons translucent, so Reduce Transparency darkens instead.
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        let receded = role == .receded
        content
            // A crossfade, so Reduce Motion needs no separate path.
            .animation(.easeOut(duration: 0.15)) {
                $0.saturation(receded ? 0.45 : 1)
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
                    .modifier(DockContextMenuSpotlight(role: index == 1 ? .owner : .receded, reduceTransparency: false))
            }
        }
        .padding(20)
    }

    #Preview("Reduce Transparency") {
        HStack(spacing: 12) {
            ForEach(Array(DockPreviewData.items.prefix(4).enumerated()), id: \.element.id) { index, item in
                Image(nsImage: item.icon).resizable().frame(width: 48, height: 48)
                    .modifier(DockContextMenuSpotlight(role: index == 1 ? .owner : .receded, reduceTransparency: true))
            }
        }
        .padding(20)
    }
#endif
