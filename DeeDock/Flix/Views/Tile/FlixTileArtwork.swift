import SwiftUI

/// The tile's picture: a light glass square holding the newest item's thumbnail, which pops in
/// when a new item arrives (a fade with Reduce Motion).
struct FlixTileArtwork: View {
    let size: CGFloat
    let thumbnail: NSImage?
    let sensitive: Bool
    let arrivals: Int
    let reduceMotion: Bool
    let reduceTransparency: Bool

    @State private var popped = true

    var body: some View {
        let unit = size / 50
        let shape = RoundedRectangle(cornerRadius: 12 * unit, style: .continuous)
        ZStack {
            shape
                .fill(reduceTransparency
                      ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                      : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.06)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 1.5 * unit, y: 1 * unit)
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "tray.full")
                        .font(.system(size: 20 * unit, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 38 * unit, height: 38 * unit)
            .blur(radius: sensitive ? 4 * unit : 0)
            .scaleEffect(popped || reduceMotion ? 1 : 0.6)
            .opacity(popped ? 1 : 0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onChange(of: arrivals) { _, _ in
            popped = false
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.55)) {
                popped = true
            }
        }
    }
}

/// "✦ 2 fit here" above the tile, in the intelligence gradient.
struct FlixFitsPill: View {
    let count: Int

    var body: some View {
        Text(.flixTileFitsPill(count))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(FlixStyle.aiButtonGradient, in: .capsule)
            .shadow(color: Color(red: 0.31, green: 0.24, blue: 0.78).opacity(0.4), radius: 6, y: 4)
            .accessibilityHidden(true)
    }
}
