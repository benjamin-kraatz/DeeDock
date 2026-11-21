import SwiftUI

/// The tile's picture: a light glass square holding the newest item's thumbnail, with the red
/// "new since you looked" badge on its corner.
///
/// Motion, from the mockup:
/// - A new item pops the thumbnail in from 60 % with ``FlixMotion/pop``.
/// - The thumbnail that replaces the type icon once it has rendered crossfades.
/// - The badge pops in when it first appears and bumps when its count rises.
///
/// With Reduce Motion all three are short fades with no scaling.
struct FlixTileArtwork: View {
    let size: CGFloat
    let thumbnail: NSImage?
    let sensitive: Bool
    let arrivals: Int
    /// The badge's text, or nil for no badge.
    var badge: String?
    let reduceMotion: Bool
    let reduceTransparency: Bool

    /// The thumbnail's pose during a pop.
    private struct Pop {
        var scale: CGFloat = 1
        var opacity: Double = 1
    }

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
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 3 * unit, style: .continuous))
                        .id(ObjectIdentifier(thumbnail))
                        .transition(.opacity)
                } else {
                    Image(systemName: "tray.full")
                        .font(.system(size: 20 * unit, weight: .medium))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .frame(width: 38 * unit, height: 38 * unit)
            .blur(radius: sensitive ? 4 * unit : 0)
            .animation(.easeOut(duration: 0.2), value: thumbnail.map(ObjectIdentifier.init))
            // Keyframes rather than a state flip: each arrival restarts the pop from 60 %, even
            // while an earlier one is still settling.
            .keyframeAnimator(initialValue: Pop(), trigger: arrivals) { content, pop in
                content.scaleEffect(reduceMotion ? 1 : pop.scale).opacity(pop.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    MoveKeyframe(0.6)
                    SpringKeyframe(1, duration: 0.6, spring: Spring(response: 0.38, dampingRatio: 0.55))
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    LinearKeyframe(1, duration: 0.19)
                }
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if let badge {
                FlixTileBadge(label: badge, iconSize: size, arrivals: arrivals, reduceMotion: reduceMotion)
                    .transition(FlixMotion.pop(reduceMotion: reduceMotion, scale: 0.4))
            }
        }
        .animation(FlixMotion.resolved(FlixMotion.pop, reduceMotion: reduceMotion), value: badge != nil)
        .accessibilityHidden(true)
    }
}

/// The dock's count badge on the Flix tile, bumping once for each arrival.
private struct FlixTileBadge: View {
    let label: String
    let iconSize: CGFloat
    let arrivals: Int
    let reduceMotion: Bool

    var body: some View {
        DockAppBadge(label: label, iconSize: iconSize, style: .count)
            .keyframeAnimator(initialValue: 1.0, trigger: arrivals) { content, scale in
                content.scaleEffect(reduceMotion ? 1 : scale)
            } keyframes: { _ in
                SpringKeyframe(1.28, duration: 0.14, spring: .snappy)
                SpringKeyframe(1, duration: 0.45, spring: Spring(response: 0.38, dampingRatio: 0.55))
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
            .contentTransition(.numericText(value: Double(count)))
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Tile artwork") {
    HStack(spacing: 24) {
        FlixTileArtwork(size: 50, thumbnail: NSImage(systemSymbolName: "photo", accessibilityDescription: nil),
                        sensitive: false, arrivals: 0, badge: "3", reduceMotion: false, reduceTransparency: false)
        FlixTileArtwork(size: 50, thumbnail: NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil),
                        sensitive: true, arrivals: 0, badge: "12", reduceMotion: false, reduceTransparency: true)
        FlixTileArtwork(size: 64, thumbnail: nil, sensitive: false, arrivals: 0, reduceMotion: true,
                        reduceTransparency: false)
        FlixFitsPill(count: 2)
    }
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
#endif
