import AppKit
import SwiftUI

/// The App Launcher tile's mark: a grid glyph on an indigo rounded square.
///
/// Shared by the dock button and the image a launcher drag carries, so both look the same.
struct LauncherTileArtwork: View {
    /// The tile's full icon size; the mark fills 85% of it like application artwork.
    let size: CGFloat

    private var markSize: CGFloat { size * 0.85 }

    var body: some View {
        Image(systemName: "square.grid.3x3.fill")
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: markSize, height: markSize)
            .background(
                LinearGradient(
                    colors: [.indigo, .indigo.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: .rect(cornerRadius: size * 0.26)
            )
    }
}

extension LauncherTileArtwork {
    /// Rasterized mark for a native drag image, centered in a `size` square.
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
