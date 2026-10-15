import SwiftUI

/// The sidebar row while it is being dragged to a new position or out of the sidebar.
///
/// Drawn in a `HubFilesOverlayWindow` so it can follow the pointer past the Hub's edge. It
/// floats at 103 % on the menu material with a soft shadow. Over a spot that removes it, the row
/// shrinks to 92 % and fades and the dark "Remove from Sidebar" label appears beneath it.
struct HubFilesSidebarLiftedRow: View {
    let symbolName: String
    let title: String
    let isRemoving: Bool
    let reduceTransparency: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HubStyle.rowRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 19, height: 19)
                Text(verbatim: title)
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(width: HubFilesSidebarMetrics.rowWidth, height: HubFilesMetrics.rowHeight)
            .background {
                // The mockup's menu glass: blurred backdrop under a tint. Opaque under Reduce
                // Transparency, where the overlay window must not show what's behind it.
                if reduceTransparency {
                    shape.fill(opaqueCard)
                } else {
                    shape.fill(.regularMaterial)
                    shape.fill(tint)
                }
            }
            .overlay { shape.strokeBorder(HubFilesTheme(scheme).strongLine, lineWidth: 0.5) }
            .shadow(color: .black.opacity(isRemoving ? 0.15 : 0.35), radius: isRemoving ? 6 : 15, y: isRemoving ? 3 : 10)
            .scaleEffect(isRemoving ? 0.92 : 1.03)
            .opacity(isRemoving ? 0.55 : 1)

            HubFilesSidebarActionLabel(action: .remove)
                .padding(.leading, 14)
                .opacity(isRemoving ? 1 : 0)
                .offset(y: isRemoving ? 0 : -4)
        }
        .padding(HubFilesSidebarMetrics.overlayInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(HubFilesMotion.animation(.spring(response: 0.24, dampingFraction: 0.85)), value: isRemoving)
    }

    /// The menu color (`--menu` in the mockup) as a solid.
    private var opaqueCard: Color {
        scheme == .dark ? Color(red: 0.157, green: 0.161, blue: 0.196) : Color(red: 0.98, green: 0.98, blue: 0.99)
    }

    /// A light wash of the menu color over the material, so the card reads as a surface and not
    /// only as blur.
    private var tint: Color {
        opaqueCard.opacity(scheme == .dark ? 0.35 : 0.5)
    }
}

/// The lifted row over a busy backdrop, as it floats over the Hub and the desktop.
private struct HubFilesSidebarLiftedRowPreview: View {
    let reduceTransparency: Bool

    var body: some View {
        VStack(spacing: 0) {
            HubFilesSidebarLiftedRow(symbolName: "folder", title: "DeeDock", isRemoving: false,
                                     reduceTransparency: reduceTransparency)
            HubFilesSidebarLiftedRow(symbolName: "arrow.down.circle", title: "Downloads", isRemoving: true,
                                     reduceTransparency: reduceTransparency)
        }
        .frame(width: HubFilesSidebarMetrics.overlaySize.width, height: HubFilesSidebarMetrics.overlaySize.height * 2)
        .padding()
        .background {
            LinearGradient(colors: [Color(red: 0.23, green: 0.16, blue: 0.42), Color(red: 0.06, green: 0.29, blue: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

#Preview("Lifted row") {
    HubFilesSidebarLiftedRowPreview(reduceTransparency: false)
}

#Preview("Lifted row · Reduce Transparency") {
    HubFilesSidebarLiftedRowPreview(reduceTransparency: true)
}

#Preview("Lifted row · light") {
    HubFilesSidebarLiftedRowPreview(reduceTransparency: false)
        .preferredColorScheme(.light)
}
