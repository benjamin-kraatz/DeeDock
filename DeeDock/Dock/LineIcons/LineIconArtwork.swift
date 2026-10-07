import AppKit
import CoreGraphics
import SwiftUI

/// Draws a catalog glyph as clean white line art, centered in a tile-sized square.
///
/// Strokes scale with the tile, so magnification thickens them in proportion instead of letting
/// small icons look heavy and large ones look thin.
struct LineIconArtwork: View {
    let glyph: LineIconGlyph
    /// The tile's full icon size in points.
    let size: CGFloat
    var color: Color = .white
    /// The choreography to pose the glyph with; nil always draws it at rest.
    var motion: LineIconMotion? = nil
    /// How far through `motion` this frame is. At 1 the glyph rests.
    var progress: Double = 1

    /// Share of the tile the 24-point box fills; the rest matches the inset of native artwork.
    static let boxFraction: CGFloat = 0.62
    /// Stroke width in catalog units. Lucide's own default of 2 reads too heavy on dark glass.
    static let strokeWidth: CGFloat = 1.5

    var body: some View {
        let box = size * Self.boxFraction * (glyph.isFilledMark ? 0.86 : 1)
        let scale = box / LineIconPath.canvas
        ZStack {
            if glyph.fill != nil {
                LineIconShape(glyph: glyph, layer: .fill, motion: motion, progress: progress).fill(color)
            }
            if glyph.stroke != nil {
                LineIconShape(glyph: glyph, layer: .stroke, motion: motion, progress: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: Self.strokeWidth * scale, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: box, height: box)
        .frame(width: size, height: size)
    }
}

/// One layer of a glyph, scaled from the 24-point catalog box into the proposed rectangle.
///
/// Mid-motion the layer is rebuilt from its posed parts and still drawn as one path. Fill parts
/// therefore keep combining under the nonzero rule, which is what lets a cutout move inside the
/// part it is cut from. At rest the catalog's merged path is used as is, so a still dock does no
/// per-part work.
struct LineIconShape: Shape {
    enum Layer { case stroke, fill }
    let glyph: LineIconGlyph
    let layer: Layer
    var motion: LineIconMotion? = nil
    var progress: Double = 1

    func path(in rect: CGRect) -> Path {
        guard let source = layer == .stroke ? glyph.stroke : glyph.fill else { return Path() }
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / LineIconPath.canvas, y: rect.height / LineIconPath.canvas)
        guard let motion, progress < 1 else { return Path(source).applying(transform) }
        var posed = Path()
        for (index, part) in (layer == .stroke ? glyph.strokeParts : glyph.fillParts).enumerated() {
            let pose = motion.pose(for: layer == .stroke ? .stroke(index) : .fill(index), at: progress,
                                   strokeCount: glyph.strokeParts.count, fillCount: glyph.fillParts.count)
            var piece = Path(part)
            if layer == .stroke, pose.trimStart > 0 || pose.trimEnd < 1 {
                // Nothing drawn yet: an empty span would otherwise leave a round-capped dot.
                guard pose.trimEnd > pose.trimStart else { continue }
                piece = piece.trimmedPath(from: pose.trimStart, to: pose.trimEnd)
            }
            posed.addPath(piece, transform: pose.transform)
        }
        return posed.applying(transform)
    }
}

/// What lights up behind a line glyph while the pointer is over its tile.
enum DockLineGlow {
    /// The app's own artwork, blurred, so each app glows in its brand colors.
    case artwork(NSImage)
    /// A shared magenta, orange, and blue spectrum for tiles without colorful artwork.
    case spectrum
}

/// A tile's line glyph with the glow its hover state calls for.
struct DockLineIcon {
    let glyph: LineIconGlyph
    var glow: DockLineGlow = .spectrum
    /// The owning dock's motion setting; `.off` keeps the glyph still.
    var motion: LineIconMotionPlayback = .hover
}

/// A line glyph over a soft colored glow that fades in on hover, playing the glyph's motion once
/// each time the highlight arrives and stays for a moment.
///
/// A tile that appears already highlighted, such as the Launcher's top result, glows without
/// playing; otherwise every keystroke of a search would set the first result moving.
///
/// The motion also plays once whenever ``attention`` changes to a new non-nil value, which is how a
/// badge arriving on the tile is announced. The dock's motion setting and Reduce Motion apply to
/// that play as well.
///
/// The dock always draws white on its dark glass; the Launcher passes `.primary` so glyphs stay
/// legible on light glass too. The glow is drawn outside the tile's square and never takes hit-testing, so it cannot change the
/// button region or click-through geometry. Reduce Transparency replaces the blurred glow with a
/// brighter glyph; Reduce Motion shows and hides it without a fade and keeps the glyph still, as
/// does the dock's own motion setting carried in ``DockLineIcon/motion``.
struct DockLineIconArtwork: View {
    let icon: DockLineIcon
    let size: CGFloat
    let hovered: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool
    var color: Color = .white
    /// Changes when news arrives on the tile, such as a higher badge count; nil while there is none.
    var attention: String? = nil

    /// How long the highlight must rest on a tile before its motion plays, so a sweep along the
    /// dock does not set every glyph off.
    static let hoverDwell: Duration = .milliseconds(70)

    /// When the highlight last arrived; nil while the tile is not highlighted, and also for a tile
    /// that appeared already highlighted.
    @State private var highlightBegan: Date?
    /// Bumped to play the motion once. Anything that should set the glyph moving does it through
    /// this one counter.
    @State private var plays = 0
    /// When the current play ends. A hover that lands sooner lets it finish instead of restarting
    /// it, which would snap the glyph back to its first frame.
    @State private var playingUntil = Date.distantPast

    private var glowing: Bool { hovered && !reduceTransparency }

    private var motion: LineIconMotion? {
        reduceMotion || !icon.motion.playsOnHover ? nil : LineIconMotionLibrary.shared.motion(for: icon.glyph)
    }

    var body: some View {
        let motion = self.motion
        // Progress rests at 1 and each play runs it from 0 back to 1, so the animator hands the
        // artwork its resting value whenever nothing is playing.
        KeyframeAnimator(initialValue: 1.0, trigger: plays) { progress in
            LineIconArtwork(glyph: icon.glyph, size: size,
                            color: color.opacity(hovered || reduceTransparency ? 1 : 0.92),
                            motion: motion, progress: progress)
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(0.0)
                LinearKeyframe(1.0, duration: motion?.duration ?? 0.01)
            }
        }
        // At rest a faint dark edge keeps white lines legible on light wallpapers seen through the glass.
        .shadow(color: glowing ? .white.opacity(0.55) : .black.opacity(0.35),
                radius: glowing ? size * 0.06 : max(0.5, size * 0.015))
        .background {
            // Inserted only while hovered: a resting dock would otherwise pay for one blur per tile.
            if glowing {
                DockLineGlowView(glow: icon.glow, size: size)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: hovered ? 0.18 : 0.32), value: glowing)
        .onChange(of: hovered) { _, highlighted in highlightBegan = highlighted ? .now : nil }
        // Restarts with every highlight change, so leaving within the dwell cancels the pending play.
        .task(id: highlightBegan) {
            guard highlightBegan != nil, let motion else { return }
            try? await Task.sleep(for: Self.hoverDwell)
            guard !Task.isCancelled else { return }
            play(motion)
        }
        .onChange(of: attention) { _, news in
            guard news != nil, let motion else { return }
            play(motion)
        }
    }

    private func play(_ motion: LineIconMotion) {
        guard Date.now >= playingUntil else { return }
        playingUntil = Date.now.addingTimeInterval(motion.duration)
        plays += 1
    }
}

/// The blurred color field behind a hovered glyph.
private struct DockLineGlowView: View {
    let glow: DockLineGlow
    let size: CGFloat

    var body: some View {
        Group {
            switch glow {
            case .artwork(let image):
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.low)
                    .saturation(1.35)
                    .frame(width: size * 0.9, height: size * 0.9)
            case .spectrum:
                Circle()
                    .fill(AngularGradient(colors: [.pink, .orange, .blue, .purple, .pink], center: .center))
                    .frame(width: size * 0.8, height: size * 0.8)
            }
        }
        .blur(radius: size * 0.26)
        .opacity(0.9)
        .frame(width: size, height: size)
    }
}

extension LineIconArtwork {
    /// Rasterized glyph for a native drag image. Call it when a drag starts, not on each pointer move.
    @MainActor static func image(glyph: LineIconGlyph, size: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content: LineIconArtwork(glyph: glyph, size: size))
        renderer.scale = 2
        renderer.isOpaque = false
        guard let cgImage = renderer.cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}

#if DEBUG
#Preview("Line glyphs, resting and hovered") {
    let glyph = LineIconGlyph(id: "preview:compass",
                              stroke: LineIconPath.parse("M22 12C22 17.52 17.52 22 12 22C6.48 22 2 17.52 2 12C2 6.48 6.48 2 12 2C17.52 2 22 6.48 22 12Z M16.24 7.76L14.44 13.17L7.76 16.24L9.56 10.83Z"),
                              fill: nil)
    HStack(spacing: 28) {
        DockLineIconArtwork(icon: DockLineIcon(glyph: glyph), size: 48, hovered: false,
                            reduceMotion: false, reduceTransparency: false)
        DockLineIconArtwork(icon: DockLineIcon(glyph: glyph), size: 48, hovered: true,
                            reduceMotion: false, reduceTransparency: false)
        DockLineIconArtwork(icon: DockLineIcon(glyph: glyph, glow: .artwork(NSImage(named: NSImage.applicationIconName)!)),
                            size: 64, hovered: true, reduceMotion: false, reduceTransparency: false)
        DockLineIconArtwork(icon: DockLineIcon(glyph: glyph), size: 48, hovered: true,
                            reduceMotion: true, reduceTransparency: true)
        // Motion switched off in Settings: glows on hover, never moves.
        DockLineIconArtwork(icon: DockLineIcon(glyph: glyph, motion: .off), size: 48, hovered: true,
                            reduceMotion: false, reduceTransparency: false)
    }
    .padding(40)
    .background(.black)
}

#Preview("Line glyph frames of a motion") {
    // A lid on a can: the lid lifts on its right hinge while the can's seam draws on.
    let glyph = LineIconGlyph(id: "preview:can",
                              stroke: LineIconPath.parse("M3 6L21 6M5 6L5 20L19 20L19 6M12 10L12 16"),
                              fill: nil)
    let motion = try? JSONDecoder().decode(LineIconMotion.self, from: Data("""
        {"duration": 1, "tracks": [
            {"parts": ["s0"], "rotate": [[0, 0], [0.4, 22, "out"], [0.9, 0]], "anchor": [21, 6]},
            {"parts": ["s2"], "draw": [[0, 0], [0.8, 1]]}]}
        """.utf8))
    HStack(spacing: 28) {
        ForEach([0.0, 0.2, 0.4, 0.7, 1.0], id: \.self) { progress in
            LineIconArtwork(glyph: glyph, size: 56, motion: motion, progress: progress)
        }
    }
    .padding(40)
    .background(.black)
}
#endif
