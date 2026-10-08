import SwiftUI

/// The display's wallpaper, blurred and dimmed, covering every window behind Harbor.
///
/// The blur is baked into the image by ``HarborWallpaperLoader``, so this view draws one static
/// layer. Without a usable wallpaper it falls back to a quiet gradient. Reduce Transparency keeps
/// the wallpaper's colors but raises the scrim until the backdrop reads as solid.
struct HarborBackdrop: View {
    let wallpaper: CGImage?
    let reduceTransparency: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var scrim: Color {
        colorScheme == .dark ? Color(red: 0.02, green: 0.03, blue: 0.05) : Color(red: 0.96, green: 0.96, blue: 0.98)
    }

    var body: some View {
        ZStack {
            if let wallpaper {
                Image(decorative: wallpaper, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            } else {
                LinearGradient(colors: colorScheme == .dark
                               ? [Color(red: 0.09, green: 0.10, blue: 0.16), Color(red: 0.02, green: 0.02, blue: 0.04)]
                               : [Color(red: 0.93, green: 0.95, blue: 0.98), Color(red: 0.84, green: 0.87, blue: 0.93)],
                               startPoint: .top, endPoint: .bottom)
            }
            scrim.opacity(reduceTransparency ? HarborStyle.reducedTransparencyScrimOpacity : HarborStyle.scrimOpacity)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Backdrop without wallpaper") {
    HarborBackdrop(wallpaper: nil, reduceTransparency: false).frame(width: 640, height: 400)
}

#Preview("Backdrop, Reduce Transparency") {
    HarborBackdrop(wallpaper: nil, reduceTransparency: true).frame(width: 640, height: 400)
}
#endif
