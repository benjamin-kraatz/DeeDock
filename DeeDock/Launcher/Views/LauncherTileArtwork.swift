import AppKit
import SwiftUI

/// The DOKK tile's face: the white DOKK mark on a dark radial gradient (the mockup's Glow tile).
///
/// Shared by the dock button and the image a tile drag carries, so both look the same. The
/// animated halo and the transfer ring belong to ``DockLauncherButton`` and are not part of this
/// artwork, so a drag image never carries motion.
struct LauncherTileArtwork: View {
    /// The tile's full icon size; the face fills 85 % of it like application artwork.
    let size: CGFloat

    private var faceSize: CGFloat { size * 0.85 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: faceSize * 0.26, style: .continuous)
        Image("DDockMark")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(.white)
            .frame(width: faceSize * 0.65)
            .frame(width: faceSize, height: faceSize)
            .background {
                // Mockup: radial-gradient(120% 120% at 30% 20%, #2a2b33, #0d0d12).
                RadialGradient(colors: [Color(red: 0x2a / 255, green: 0x2b / 255, blue: 0x33 / 255),
                                        Color(red: 0x0d / 255, green: 0x0d / 255, blue: 0x12 / 255)],
                               center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: faceSize * 1.2)
                    .clipShape(shape)
            }
            .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension LauncherTileArtwork {
    /// Rasterized face for a native drag image, centered in a `size` square.
    ///
    /// `ImageRenderer` walks the view tree, so call this once per drag, not per refresh.
    static func image(size: CGFloat) -> NSImage {
        let renderer = ImageRenderer(content: LauncherTileArtwork(size: size).frame(width: size, height: size))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let cgImage = renderer.cgImage else { return NSImage(size: NSSize(width: size, height: size)) }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}

#Preview {
    HStack(spacing: 16) {
        LauncherTileArtwork(size: 48)
        LauncherTileArtwork(size: 64)
        Image(nsImage: LauncherTileArtwork.image(size: 64))
    }
    .padding()
}
